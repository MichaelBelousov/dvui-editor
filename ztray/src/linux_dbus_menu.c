/*
 * Session-bus com.canonical.dbusmenu server (DBusMenu / global menu clients).
 * Built only when the Zig build host is Linux (<dbus/dbus.h> and -ldbus-1).
 */
#include <dbus/dbus.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#define ZTRAY_MENU_PATH "/org/ztray/DvuiEditor/Menu"
#define ZTRAY_BUS_NAME "org.ztray.DvuiEditor"
#define ZTRAY_MAX_ITEMS 512

typedef struct {
    int32_t id;
    int32_t parent_id;
    int32_t action_id;
    uint32_t flags;
    char *label;
} ZTrayItem;

static ZTrayItem g_items[ZTRAY_MAX_ITEMS];
static int g_nitems;
static dbus_uint32_t g_revision;
static DBusConnection *g_conn;
static atomic_int g_pending_action = -1;

enum { FLAG_SEPARATOR = 1u, FLAG_SUBMENU = 2u, FLAG_DISABLED = 4u };

static void free_items(void) {
    for (int i = 0; i < g_nitems; i++) {
        free(g_items[i].label);
        g_items[i].label = NULL;
    }
    g_nitems = 0;
}

static ZTrayItem *find_item(int32_t id) {
    for (int i = 0; i < g_nitems; i++) {
        if (g_items[i].id == id) return &g_items[i];
    }
    return NULL;
}

static int append_dict_string(DBusMessageIter *dict, const char *key, const char *val) {
    DBusMessageIter entry, variant;
    if (!dbus_message_iter_open_container(dict, DBUS_TYPE_DICT_ENTRY, NULL, &entry)) return 0;
    char *k = (char *)key;
    if (!dbus_message_iter_append_basic(&entry, DBUS_TYPE_STRING, &k)) return 0;
    if (!dbus_message_iter_open_container(&entry, DBUS_TYPE_VARIANT, "s", &variant)) return 0;
    char *v = (char *)val;
    if (!dbus_message_iter_append_basic(&variant, DBUS_TYPE_STRING, &v)) return 0;
    if (!dbus_message_iter_close_container(&entry, &variant)) return 0;
    if (!dbus_message_iter_close_container(dict, &entry)) return 0;
    return 1;
}

static int append_dict_bool(DBusMessageIter *dict, const char *key, dbus_bool_t val) {
    DBusMessageIter entry, variant;
    if (!dbus_message_iter_open_container(dict, DBUS_TYPE_DICT_ENTRY, NULL, &entry)) return 0;
    char *k = (char *)key;
    if (!dbus_message_iter_append_basic(&entry, DBUS_TYPE_STRING, &k)) return 0;
    if (!dbus_message_iter_open_container(&entry, DBUS_TYPE_VARIANT, "b", &variant)) return 0;
    if (!dbus_message_iter_append_basic(&variant, DBUS_TYPE_BOOLEAN, &val)) return 0;
    if (!dbus_message_iter_close_container(&entry, &variant)) return 0;
    if (!dbus_message_iter_close_container(dict, &entry)) return 0;
    return 1;
}

static int append_properties(DBusMessageIter *dict, ZTrayItem *node) {
    const char *empty = "";
    if (node->flags & FLAG_SEPARATOR) {
        if (!append_dict_string(dict, "type", "separator")) return 0;
        if (!append_dict_string(dict, "label", empty)) return 0;
        return 1;
    }
    if (!append_dict_string(dict, "type", "standard")) return 0;
    const char *lab = node->label ? node->label : empty;
    if (!append_dict_string(dict, "label", lab)) return 0;
    dbus_bool_t en = (node->flags & FLAG_DISABLED) ? FALSE : TRUE;
    if (!append_dict_bool(dict, "enabled", en)) return 0;
    if (node->flags & FLAG_SUBMENU) {
        if (!append_dict_string(dict, "children-display", "submenu")) return 0;
    }
    return 1;
}

static int append_layout_recursive(DBusMessageIter *arr, int32_t node_id, int32_t depth);

static int append_one_child_variant(DBusMessageIter *arr, int32_t child_id, int32_t depth) {
    ZTrayItem *ch = find_item(child_id);
    if (!ch) return 1;

    DBusMessageIter var, st, dict, ch_arr;
    if (!dbus_message_iter_open_container(arr, DBUS_TYPE_VARIANT, "(ia{sv}av)", &var)) return 0;
    if (!dbus_message_iter_open_container(&var, DBUS_TYPE_STRUCT, NULL, &st)) return 0;

    if (!dbus_message_iter_append_basic(&st, DBUS_TYPE_INT32, &ch->id)) return 0;

    if (!dbus_message_iter_open_container(&st, DBUS_TYPE_ARRAY, "{sv}", &dict)) return 0;
    if (!append_properties(&dict, ch)) return 0;
    if (!dbus_message_iter_close_container(&st, &dict)) return 0;

    if (!dbus_message_iter_open_container(&st, DBUS_TYPE_ARRAY, "v", &ch_arr)) return 0;
    if (depth != 0 && (ch->flags & FLAG_SUBMENU)) {
        int32_t next_depth = (depth > 0) ? (depth - 1) : depth;
        if (!append_layout_recursive(&ch_arr, ch->id, next_depth)) return 0;
    }
    if (!dbus_message_iter_close_container(&st, &ch_arr)) return 0;

    if (!dbus_message_iter_close_container(&var, &st)) return 0;
    if (!dbus_message_iter_close_container(arr, &var)) return 0;
    return 1;
}

static int append_layout_recursive(DBusMessageIter *arr, int32_t node_id, int32_t depth) {
    for (int i = 0; i < g_nitems; i++) {
        if (g_items[i].parent_id != node_id) continue;
        if (!append_one_child_variant(arr, g_items[i].id, depth)) return 0;
    }
    return 1;
}

static DBusHandlerResult reply_introspect(DBusMessage *msg) {
    static const char *const intro =
        "<!DOCTYPE node PUBLIC \"-//freedesktop//DTD D-BUS Object Introspection 1.0//EN\"\n"
        "\"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd\">\n"
        "<node>\n"
        " <interface name=\"org.freedesktop.DBus.Introspectable\">\n"
        "  <method name=\"Introspect\">\n"
        "   <arg name=\"data\" type=\"s\" direction=\"out\"/>\n"
        "  </method>\n"
        " </interface>\n"
        " <interface name=\"org.freedesktop.DBus.Properties\">\n"
        "  <method name=\"Get\">\n"
        "   <arg name=\"interface\" type=\"s\" direction=\"in\"/>\n"
        "   <arg name=\"property\" type=\"s\" direction=\"in\"/>\n"
        "   <arg name=\"value\" type=\"v\" direction=\"out\"/>\n"
        "  </method>\n"
        " </interface>\n"
        " <interface name=\"com.canonical.dbusmenu\">\n"
        "  <method name=\"GetLayout\">\n"
        "   <arg name=\"parentId\" type=\"i\" direction=\"in\"/>\n"
        "   <arg name=\"recursionDepth\" type=\"i\" direction=\"in\"/>\n"
        "   <arg name=\"propertyNames\" type=\"as\" direction=\"in\"/>\n"
        "   <arg name=\"revision\" type=\"u\" direction=\"out\"/>\n"
        "   <arg name=\"layout\" type=\"(ia{sv}av)\" direction=\"out\"/>\n"
        "  </method>\n"
        "  <method name=\"Event\">\n"
        "   <arg name=\"id\" type=\"i\" direction=\"in\"/>\n"
        "   <arg name=\"eventId\" type=\"s\" direction=\"in\"/>\n"
        "   <arg name=\"data\" type=\"v\" direction=\"in\"/>\n"
        "   <arg name=\"timestamp\" type=\"u\" direction=\"in\"/>\n"
        "  </method>\n"
        "  <method name=\"AboutToShow\">\n"
        "   <arg name=\"id\" type=\"i\" direction=\"in\"/>\n"
        "  </method>\n"
        "  <signal name=\"LayoutUpdated\">\n"
        "   <arg name=\"revision\" type=\"u\"/>\n"
        "   <arg name=\"parent\" type=\"i\"/>\n"
        "  </signal>\n"
        " </interface>\n"
        "</node>\n";

    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) return DBUS_HANDLER_RESULT_HANDLED;
    DBusMessageIter iter;
    dbus_message_iter_init_append(reply, &iter);
    char *s = (char *)intro;
    dbus_message_iter_append_basic(&iter, DBUS_TYPE_STRING, &s);
    dbus_connection_send(g_conn, reply, NULL);
    dbus_message_unref(reply);
    return DBUS_HANDLER_RESULT_HANDLED;
}

static DBusHandlerResult reply_properties_get(DBusMessage *msg) {
    DBusMessageIter args;
    if (!dbus_message_iter_init(msg, &args)) return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    const char *iface = NULL;
    dbus_message_iter_get_basic(&args, &iface);
    if (!dbus_message_iter_next(&args)) return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    const char *prop = NULL;
    dbus_message_iter_get_basic(&args, &prop);
    if (!iface || !prop || strcmp(iface, "com.canonical.dbusmenu") != 0 || strcmp(prop, "Version") != 0)
        return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;

    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) return DBUS_HANDLER_RESULT_HANDLED;
    DBusMessageIter iter, variant;
    dbus_uint32_t ver = 4;
    dbus_message_iter_init_append(reply, &iter);
    dbus_message_iter_open_container(&iter, DBUS_TYPE_VARIANT, "u", &variant);
    dbus_message_iter_append_basic(&variant, DBUS_TYPE_UINT32, &ver);
    dbus_message_iter_close_container(&iter, &variant);
    dbus_connection_send(g_conn, reply, NULL);
    dbus_message_unref(reply);
    return DBUS_HANDLER_RESULT_HANDLED;
}

static DBusHandlerResult reply_empty(DBusMessage *msg) {
    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (reply) {
        dbus_connection_send(g_conn, reply, NULL);
        dbus_message_unref(reply);
    }
    return DBUS_HANDLER_RESULT_HANDLED;
}

static DBusHandlerResult handle_get_layout(DBusMessage *msg) {
    DBusMessageIter args;
    int32_t parent_id = 0;
    int32_t depth = -1;
    if (!dbus_message_iter_init(msg, &args)) return DBUS_HANDLER_RESULT_HANDLED;
    if (dbus_message_iter_get_arg_type(&args) != DBUS_TYPE_INT32) return reply_empty(msg);
    dbus_message_iter_get_basic(&args, &parent_id);
    if (!dbus_message_iter_next(&args)) return reply_empty(msg);
    dbus_message_iter_get_basic(&args, &depth);
    (void)dbus_message_iter_next(&args); /* optional propertyNames (as) */

    ZTrayItem *node = find_item(parent_id);
    if (!node && parent_id != 0) return reply_empty(msg);
    int32_t nid = node ? node->id : 0;

    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) return DBUS_HANDLER_RESULT_HANDLED;

    DBusMessageIter iter, outer, layout_struct, dict, av;
    dbus_message_iter_init_append(reply, &iter);
    if (!dbus_message_iter_open_container(&iter, DBUS_TYPE_STRUCT, NULL, &outer)) goto fail;
    if (!dbus_message_iter_append_basic(&outer, DBUS_TYPE_UINT32, &g_revision)) goto fail;

    if (!dbus_message_iter_open_container(&outer, DBUS_TYPE_STRUCT, NULL, &layout_struct)) goto fail;
    if (!dbus_message_iter_append_basic(&layout_struct, DBUS_TYPE_INT32, &nid)) goto fail;

    if (!dbus_message_iter_open_container(&layout_struct, DBUS_TYPE_ARRAY, "{sv}", &dict)) goto fail;
    if (node) {
        if (!append_properties(&dict, node)) goto fail;
    } else {
        const char *empty = "";
        if (!append_dict_string(&dict, "type", "standard")) goto fail;
        if (!append_dict_string(&dict, "label", empty)) goto fail;
        dbus_bool_t t = TRUE;
        if (!append_dict_bool(&dict, "enabled", t)) goto fail;
        if (!append_dict_string(&dict, "children-display", "submenu")) goto fail;
    }
    if (!dbus_message_iter_close_container(&layout_struct, &dict)) goto fail;

    if (!dbus_message_iter_open_container(&layout_struct, DBUS_TYPE_ARRAY, "v", &av)) goto fail;
    if (depth != 0) {
        if (!append_layout_recursive(&av, parent_id, depth)) goto fail;
    }
    if (!dbus_message_iter_close_container(&layout_struct, &av)) goto fail;
    if (!dbus_message_iter_close_container(&outer, &layout_struct)) goto fail;
    if (!dbus_message_iter_close_container(&iter, &outer)) goto fail;

    dbus_connection_send(g_conn, reply, NULL);
    dbus_message_unref(reply);
    return DBUS_HANDLER_RESULT_HANDLED;
fail:
    dbus_message_unref(reply);
    return DBUS_HANDLER_RESULT_HANDLED;
}

static DBusHandlerResult handle_event(DBusMessage *msg) {
    DBusMessageIter args;
    if (!dbus_message_iter_init(msg, &args)) return reply_empty(msg);
    int32_t id = 0;
    dbus_message_iter_get_basic(&args, &id);
    if (!dbus_message_iter_next(&args)) return reply_empty(msg);
    const char *ev = NULL;
    dbus_message_iter_get_basic(&args, &ev);
    (void)dbus_message_iter_next(&args); /* data: variant */
    (void)dbus_message_iter_next(&args); /* timestamp: uint32 */
    if (ev && strcmp(ev, "clicked") == 0) {
        ZTrayItem *it = find_item(id);
        if (it && it->action_id >= 0) atomic_store(&g_pending_action, it->action_id);
    }
    return reply_empty(msg);
}

static DBusHandlerResult filter_message(DBusConnection *connection, DBusMessage *message, void *user_data) {
    (void)connection;
    (void)user_data;
    if (dbus_message_get_type(message) != DBUS_MESSAGE_TYPE_METHOD_CALL) return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    const char *path = dbus_message_get_path(message);
    if (!path || strcmp(path, ZTRAY_MENU_PATH) != 0) return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;

    const char *iface = dbus_message_get_interface(message);
    const char *member = dbus_message_get_member(message);
    if (!iface || !member) return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;

    if (strcmp(iface, "org.freedesktop.DBus.Introspectable") == 0 && strcmp(member, "Introspect") == 0)
        return reply_introspect(message);
    if (strcmp(iface, "org.freedesktop.DBus.Properties") == 0 && strcmp(member, "Get") == 0)
        return reply_properties_get(message);
    if (strcmp(iface, "com.canonical.dbusmenu") == 0) {
        if (strcmp(member, "GetLayout") == 0) return handle_get_layout(message);
        if (strcmp(member, "Event") == 0) return handle_event(message);
        if (strcmp(member, "AboutToShow") == 0) return reply_empty(message);
        if (strcmp(member, "EventGroup") == 0) return reply_empty(message);
    }
    return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
}

static void emit_layout_updated(void) {
    if (!g_conn) return;
    DBusMessage *sig = dbus_message_new_signal(ZTRAY_MENU_PATH, "com.canonical.dbusmenu", "LayoutUpdated");
    if (!sig) return;
    DBusMessageIter iter;
    dbus_message_iter_init_append(sig, &iter);
    dbus_int32_t root = 0;
    dbus_message_iter_append_basic(&iter, DBUS_TYPE_UINT32, &g_revision);
    dbus_message_iter_append_basic(&iter, DBUS_TYPE_INT32, &root);
    dbus_connection_send(g_conn, sig, NULL);
    dbus_message_unref(sig);
}

int ztray_linux_dbus_init(void) {
    if (g_conn) return 1;
    DBusError err;
    dbus_error_init(&err);
    g_conn = dbus_bus_get(DBUS_BUS_SESSION, &err);
    if (!g_conn) {
        dbus_error_free(&err);
        return 0;
    }
    dbus_connection_add_filter(g_conn, filter_message, NULL, NULL);
    dbus_uint32_t flags = DBUS_NAME_FLAG_REPLACE_EXISTING;
    dbus_uint32_t reply = 0;
    (void)dbus_bus_request_name(g_conn, ZTRAY_BUS_NAME, flags, &reply);
    return 1;
}

void ztray_linux_dbus_shutdown(void) {
    if (!g_conn) return;
    dbus_connection_remove_filter(g_conn, filter_message, NULL);
    dbus_connection_unref(g_conn);
    g_conn = NULL;
    free_items();
    g_revision = 0;
}

typedef struct {
    int32_t id;
    int32_t parent_id;
    int32_t action_id;
    uint32_t flags;
    const char *label;
} ZTrayLinuxItem;

int ztray_linux_dbus_set_items(const ZTrayLinuxItem *items, int n) {
    if (n < 0 || n > ZTRAY_MAX_ITEMS) return 0;
    free_items();
    for (int i = 0; i < n; i++) {
        g_items[i].id = items[i].id;
        g_items[i].parent_id = items[i].parent_id;
        g_items[i].action_id = items[i].action_id;
        g_items[i].flags = items[i].flags;
        g_items[i].label = items[i].label ? strdup(items[i].label) : strdup("");
        if (!g_items[i].label) {
            free_items();
            return 0;
        }
    }
    g_nitems = n;
    if (g_revision == 0xFFFFFFFFu)
        g_revision = 1;
    else
        g_revision++;
    emit_layout_updated();
    return 1;
}

void ztray_linux_dbus_dispatch(void) {
    if (g_conn) dbus_connection_read_write_dispatch(g_conn, 0);
}

int ztray_linux_dbus_take_pending(void) {
    return atomic_exchange(&g_pending_action, -1);
}
