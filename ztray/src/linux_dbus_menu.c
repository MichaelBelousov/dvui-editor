/*
 * Session D-Bus: com.canonical.dbusmenu for menubar + tray, and org.kde.StatusNotifierItem for Linux tray.
 * Built only when the Zig build host is Linux (<dbus/dbus.h> and -ldbus-1).
 */
#include <dbus/dbus.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void ztray_linux_tray_shutdown(void);

#define ZTRAY_MENU_PATH "/org/ztray/app/Menu"
#define ZTRAY_TRAY_MENU_PATH "/org/ztray/app/TrayMenu"
#define ZTRAY_SNI_PATH "/org/ztray/app/SNI"
#define ZTRAY_MAX_ITEMS 512

typedef struct {
    int32_t id;
    int32_t parent_id;
    int32_t action_id;
    uint32_t flags;
    char *label;
} ZTrayItem;

static ZTrayItem g_menubar_items[ZTRAY_MAX_ITEMS];
static int g_n_menubar;
static dbus_uint32_t g_menubar_revision;
static atomic_int g_pending_menubar_action = -1;

static ZTrayItem g_tray_items[ZTRAY_MAX_ITEMS];
static int g_n_tray;
static dbus_uint32_t g_tray_revision;
static atomic_int g_pending_tray_action = -1;

static DBusConnection *g_conn;
static char *g_tray_tooltip = NULL;
static char *g_tray_icon_name = NULL;
static int g_tray_sni_active;

enum { FLAG_SEPARATOR = 1u, FLAG_SUBMENU = 2u, FLAG_DISABLED = 4u };

static void free_menubar_items(void) {
    for (int i = 0; i < g_n_menubar; i++) {
        free(g_menubar_items[i].label);
        g_menubar_items[i].label = NULL;
    }
    g_n_menubar = 0;
}

static void free_tray_items(void) {
    for (int i = 0; i < g_n_tray; i++) {
        free(g_tray_items[i].label);
        g_tray_items[i].label = NULL;
    }
    g_n_tray = 0;
}

static ZTrayItem *find_in(ZTrayItem *arr, int n, int32_t id) {
    for (int i = 0; i < n; i++) {
        if (arr[i].id == id) return &arr[i];
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

static int append_layout_recursive(DBusMessageIter *arr, ZTrayItem *items, int n, int32_t node_id, int32_t depth);

static int append_one_child_variant(DBusMessageIter *arr, ZTrayItem *items, int n, int32_t child_id, int32_t depth) {
    ZTrayItem *ch = find_in(items, n, child_id);
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
        if (!append_layout_recursive(&ch_arr, items, n, ch->id, next_depth)) return 0;
    }
    if (!dbus_message_iter_close_container(&st, &ch_arr)) return 0;

    if (!dbus_message_iter_close_container(&var, &st)) return 0;
    if (!dbus_message_iter_close_container(arr, &var)) return 0;
    return 1;
}

static int append_layout_recursive(DBusMessageIter *arr, ZTrayItem *items, int n, int32_t node_id, int32_t depth) {
    for (int i = 0; i < n; i++) {
        if (items[i].parent_id != node_id) continue;
        if (!append_one_child_variant(arr, items, n, items[i].id, depth)) return 0;
    }
    return 1;
}

static DBusHandlerResult reply_introspect_menu(DBusMessage *msg) {
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

static DBusHandlerResult reply_introspect_sni(DBusMessage *msg) {
    static const char *const intro =
        "<!DOCTYPE node PUBLIC \"-//freedesktop//DTD D-BUS Object Introspection 1.0//EN\"\n"
        "\"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd\">\n"
        "<node>\n"
        " <interface name=\"org.freedesktop.DBus.Introspectable\">\n"
        "  <method name=\"Introspect\"><arg name=\"data\" type=\"s\" direction=\"out\"/></method>\n"
        " </interface>\n"
        " <interface name=\"org.freedesktop.DBus.Properties\">\n"
        "  <method name=\"Get\">\n"
        "   <arg name=\"interface\" type=\"s\" direction=\"in\"/>\n"
        "   <arg name=\"property\" type=\"s\" direction=\"in\"/>\n"
        "   <arg name=\"value\" type=\"v\" direction=\"out\"/>\n"
        "  </method>\n"
        " </interface>\n"
        " <interface name=\"org.kde.StatusNotifierItem\">\n"
        "  <property name=\"Category\" type=\"s\" access=\"read\"/>\n"
        "  <property name=\"Id\" type=\"s\" access=\"read\"/>\n"
        "  <property name=\"Title\" type=\"s\" access=\"read\"/>\n"
        "  <property name=\"Status\" type=\"s\" access=\"read\"/>\n"
        "  <property name=\"IconName\" type=\"s\" access=\"read\"/>\n"
        "  <property name=\"Menu\" type=\"o\" access=\"read\"/>\n"
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

static DBusHandlerResult reply_properties_dbusmenu_version(DBusMessage *msg) {
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

static DBusHandlerResult reply_sni_property(DBusMessage *msg, const char *prop) {
    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) return DBUS_HANDLER_RESULT_HANDLED;
    DBusMessageIter iter, variant;

    dbus_message_iter_init_append(reply, &iter);

    if (strcmp(prop, "Category") == 0) {
        const char *v = "ApplicationStatus";
        dbus_message_iter_open_container(&iter, DBUS_TYPE_VARIANT, "s", &variant);
        dbus_message_iter_append_basic(&variant, DBUS_TYPE_STRING, &v);
        dbus_message_iter_close_container(&iter, &variant);
    } else if (strcmp(prop, "Id") == 0) {
        const char *v = "ztray";
        dbus_message_iter_open_container(&iter, DBUS_TYPE_VARIANT, "s", &variant);
        dbus_message_iter_append_basic(&variant, DBUS_TYPE_STRING, &v);
        dbus_message_iter_close_container(&iter, &variant);
    } else if (strcmp(prop, "Title") == 0) {
        const char *v = g_tray_tooltip ? g_tray_tooltip : "ztray";
        dbus_message_iter_open_container(&iter, DBUS_TYPE_VARIANT, "s", &variant);
        dbus_message_iter_append_basic(&variant, DBUS_TYPE_STRING, &v);
        dbus_message_iter_close_container(&iter, &variant);
    } else if (strcmp(prop, "Status") == 0) {
        const char *v = g_tray_sni_active ? "Active" : "Passive";
        dbus_message_iter_open_container(&iter, DBUS_TYPE_VARIANT, "s", &variant);
        dbus_message_iter_append_basic(&variant, DBUS_TYPE_STRING, &v);
        dbus_message_iter_close_container(&iter, &variant);
    } else if (strcmp(prop, "IconName") == 0) {
        const char *v = g_tray_icon_name ? g_tray_icon_name : "application-x-executable";
        dbus_message_iter_open_container(&iter, DBUS_TYPE_VARIANT, "s", &variant);
        dbus_message_iter_append_basic(&variant, DBUS_TYPE_STRING, &v);
        dbus_message_iter_close_container(&iter, &variant);
    } else if (strcmp(prop, "Menu") == 0) {
        const char *menu_obj_path = ZTRAY_TRAY_MENU_PATH;
        dbus_message_iter_open_container(&iter, DBUS_TYPE_VARIANT, "o", &variant);
        dbus_message_iter_append_basic(&variant, DBUS_TYPE_OBJECT_PATH, &menu_obj_path);
        dbus_message_iter_close_container(&iter, &variant);
    } else {
        dbus_message_unref(reply);
        return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    }

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

/* Properties.Get: args are (interface_name, property_name) per spec */
static DBusHandlerResult handle_properties_get_v2(const char *path, DBusMessage *msg) {
    DBusMessageIter args;
    if (!dbus_message_iter_init(msg, &args)) return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    const char *iface = NULL;
    dbus_message_iter_get_basic(&args, &iface);
    if (!dbus_message_iter_next(&args)) return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    const char *prop = NULL;
    dbus_message_iter_get_basic(&args, &prop);
    if (!iface || !prop) return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;

    if ((strcmp(path, ZTRAY_MENU_PATH) == 0 || strcmp(path, ZTRAY_TRAY_MENU_PATH) == 0) &&
        strcmp(iface, "com.canonical.dbusmenu") == 0 && strcmp(prop, "Version") == 0)
        return reply_properties_dbusmenu_version(msg);

    if (strcmp(path, ZTRAY_SNI_PATH) == 0 && strcmp(iface, "org.kde.StatusNotifierItem") == 0)
        return reply_sni_property(msg, prop);

    return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
}

static DBusHandlerResult handle_get_layout(const char *path, DBusMessage *msg) {
    ZTrayItem *items;
    int n;
    dbus_uint32_t *revision;
    if (strcmp(path, ZTRAY_MENU_PATH) == 0) {
        items = g_menubar_items;
        n = g_n_menubar;
        revision = &g_menubar_revision;
    } else {
        items = g_tray_items;
        n = g_n_tray;
        revision = &g_tray_revision;
    }

    DBusMessageIter args;
    int32_t parent_id = 0;
    int32_t depth = -1;
    if (!dbus_message_iter_init(msg, &args)) return DBUS_HANDLER_RESULT_HANDLED;
    if (dbus_message_iter_get_arg_type(&args) != DBUS_TYPE_INT32) return reply_empty(msg);
    dbus_message_iter_get_basic(&args, &parent_id);
    if (!dbus_message_iter_next(&args)) return reply_empty(msg);
    dbus_message_iter_get_basic(&args, &depth);
    (void)dbus_message_iter_next(&args);

    ZTrayItem *node = find_in(items, n, parent_id);
    if (!node && parent_id != 0) return reply_empty(msg);
    int32_t nid = node ? node->id : 0;

    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) return DBUS_HANDLER_RESULT_HANDLED;

    DBusMessageIter iter, outer, layout_struct, dict, av;
    dbus_message_iter_init_append(reply, &iter);
    if (!dbus_message_iter_open_container(&iter, DBUS_TYPE_STRUCT, NULL, &outer)) goto fail;
    dbus_uint32_t rev_copy = *revision;
    if (!dbus_message_iter_append_basic(&outer, DBUS_TYPE_UINT32, &rev_copy)) goto fail;

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
        if (!append_layout_recursive(&av, items, n, parent_id, depth)) goto fail;
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

static DBusHandlerResult handle_event(const char *path, DBusMessage *msg) {
    ZTrayItem *items;
    int n;
    atomic_int *pending;
    if (strcmp(path, ZTRAY_MENU_PATH) == 0) {
        items = g_menubar_items;
        n = g_n_menubar;
        pending = &g_pending_menubar_action;
    } else {
        items = g_tray_items;
        n = g_n_tray;
        pending = &g_pending_tray_action;
    }

    DBusMessageIter args;
    if (!dbus_message_iter_init(msg, &args)) return reply_empty(msg);
    int32_t id = 0;
    dbus_message_iter_get_basic(&args, &id);
    if (!dbus_message_iter_next(&args)) return reply_empty(msg);
    const char *ev = NULL;
    dbus_message_iter_get_basic(&args, &ev);
    (void)dbus_message_iter_next(&args);
    (void)dbus_message_iter_next(&args);
    if (ev && strcmp(ev, "clicked") == 0) {
        ZTrayItem *it = find_in(items, n, id);
        if (it && it->action_id >= 0) atomic_store(pending, it->action_id);
    }
    return reply_empty(msg);
}

static void emit_layout_updated(const char *path, dbus_uint32_t rev) {
    if (!g_conn) return;
    DBusMessage *sig = dbus_message_new_signal(path, "com.canonical.dbusmenu", "LayoutUpdated");
    if (!sig) return;
    DBusMessageIter iter;
    dbus_message_iter_init_append(sig, &iter);
    dbus_uint32_t r = rev;
    dbus_int32_t root = 0;
    dbus_message_iter_append_basic(&iter, DBUS_TYPE_UINT32, &r);
    dbus_message_iter_append_basic(&iter, DBUS_TYPE_INT32, &root);
    dbus_connection_send(g_conn, sig, NULL);
    dbus_message_unref(sig);
}

static int register_sni_watcher(void) {
    DBusMessage *msg = dbus_message_new_method_call(
        "org.kde.StatusNotifierWatcher",
        "/StatusNotifierWatcher",
        "org.kde.StatusNotifierWatcher",
        "RegisterStatusNotifierItem");
    if (!msg) return 0;
    DBusMessageIter iter;
    dbus_message_iter_init_append(msg, &iter);
    const char *item_path = ZTRAY_SNI_PATH;
    if (!dbus_message_iter_append_basic(&iter, DBUS_TYPE_STRING, &item_path)) {
        dbus_message_unref(msg);
        return 0;
    }
    DBusPendingCall *pending = NULL;
    if (!dbus_connection_send_with_reply(g_conn, msg, &pending, 3000)) {
        dbus_message_unref(msg);
        return 0;
    }
    dbus_message_unref(msg);
    if (pending) {
        dbus_pending_call_block(pending);
        DBusMessage *reply = dbus_pending_call_steal_reply(pending);
        dbus_pending_call_unref(pending);
        if (reply) dbus_message_unref(reply);
    }
    return 1;
}

static DBusHandlerResult filter_message(DBusConnection *connection, DBusMessage *message, void *user_data) {
    (void)connection;
    (void)user_data;
    if (dbus_message_get_type(message) != DBUS_MESSAGE_TYPE_METHOD_CALL) return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    const char *path = dbus_message_get_path(message);
    if (!path) return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;

    const char *iface = dbus_message_get_interface(message);
    const char *member = dbus_message_get_member(message);
    if (!iface || !member) return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;

    if (strcmp(path, ZTRAY_MENU_PATH) == 0 || strcmp(path, ZTRAY_TRAY_MENU_PATH) == 0) {
        if (strcmp(iface, "org.freedesktop.DBus.Introspectable") == 0 && strcmp(member, "Introspect") == 0)
            return reply_introspect_menu(message);
        if (strcmp(iface, "org.freedesktop.DBus.Properties") == 0 && strcmp(member, "Get") == 0)
            return handle_properties_get_v2(path, message);
        if (strcmp(iface, "com.canonical.dbusmenu") == 0) {
            if (strcmp(member, "GetLayout") == 0) return handle_get_layout(path, message);
            if (strcmp(member, "Event") == 0) return handle_event(path, message);
            if (strcmp(member, "AboutToShow") == 0) return reply_empty(message);
            if (strcmp(member, "EventGroup") == 0) return reply_empty(message);
        }
        return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    }

    if (strcmp(path, ZTRAY_SNI_PATH) == 0) {
        if (strcmp(iface, "org.freedesktop.DBus.Introspectable") == 0 && strcmp(member, "Introspect") == 0)
            return reply_introspect_sni(message);
        if (strcmp(iface, "org.freedesktop.DBus.Properties") == 0 && strcmp(member, "Get") == 0)
            return handle_properties_get_v2(path, message);
        return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    }

    return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
}

/* 1 = com.canonical.AppMenu.Registrar has an owner, 0 = no owner, -1 = error / unknown */
int ztray_linux_appmenu_registrar_has_owner(void) {
    DBusError err;
    dbus_error_init(&err);
    DBusConnection *conn = dbus_bus_get(DBUS_BUS_SESSION, &err);
    if (!conn) {
        dbus_error_free(&err);
        return -1;
    }

    DBusMessage *msg = dbus_message_new_method_call(
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus",
        "NameHasOwner");
    if (!msg) {
        dbus_connection_unref(conn);
        return -1;
    }

    const char *registrar = "com.canonical.AppMenu.Registrar";
    if (!dbus_message_append_args(msg, DBUS_TYPE_STRING, &registrar, DBUS_TYPE_INVALID)) {
        dbus_message_unref(msg);
        dbus_connection_unref(conn);
        return -1;
    }

    DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 5000, &err);
    dbus_message_unref(msg);
    if (!reply) {
        dbus_error_free(&err);
        dbus_connection_unref(conn);
        return -1;
    }

    if (dbus_message_get_type(reply) == DBUS_MESSAGE_TYPE_ERROR) {
        dbus_message_unref(reply);
        dbus_connection_unref(conn);
        return -1;
    }

    DBusMessageIter args;
    if (!dbus_message_iter_init(reply, &args)) {
        dbus_message_unref(reply);
        dbus_connection_unref(conn);
        return -1;
    }

    if (dbus_message_iter_get_arg_type(&args) != DBUS_TYPE_BOOLEAN) {
        dbus_message_unref(reply);
        dbus_connection_unref(conn);
        return -1;
    }

    dbus_bool_t has_owner = FALSE;
    dbus_message_iter_get_basic(&args, &has_owner);

    dbus_message_unref(reply);
    dbus_connection_unref(conn);
    return has_owner ? 1 : 0;
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
    char bus_name[64];
    snprintf(bus_name, sizeof(bus_name), "org.ztray.app%d", (int)getpid());
    dbus_uint32_t flags = DBUS_NAME_FLAG_DO_NOT_QUEUE;
    dbus_uint32_t reply = 0;
    (void)dbus_bus_request_name(g_conn, bus_name, flags, &reply);
    return 1;
}

void ztray_linux_dbus_shutdown(void) {
    if (!g_conn) return;
    ztray_linux_tray_shutdown();
    dbus_connection_remove_filter(g_conn, filter_message, NULL);
    dbus_connection_unref(g_conn);
    g_conn = NULL;
    free_menubar_items();
    g_menubar_revision = 0;
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
    free_menubar_items();
    for (int i = 0; i < n; i++) {
        g_menubar_items[i].id = items[i].id;
        g_menubar_items[i].parent_id = items[i].parent_id;
        g_menubar_items[i].action_id = items[i].action_id;
        g_menubar_items[i].flags = items[i].flags;
        g_menubar_items[i].label = items[i].label ? strdup(items[i].label) : strdup("");
        if (!g_menubar_items[i].label) {
            free_menubar_items();
            return 0;
        }
    }
    g_n_menubar = n;
    if (g_menubar_revision == 0xFFFFFFFFu)
        g_menubar_revision = 1;
    else
        g_menubar_revision++;
    emit_layout_updated(ZTRAY_MENU_PATH, g_menubar_revision);
    return 1;
}

int ztray_linux_tray_set_items(const ZTrayLinuxItem *items, int n) {
    if (n < 0 || n > ZTRAY_MAX_ITEMS) return 0;
    free_tray_items();
    for (int i = 0; i < n; i++) {
        g_tray_items[i].id = items[i].id;
        g_tray_items[i].parent_id = items[i].parent_id;
        g_tray_items[i].action_id = items[i].action_id;
        g_tray_items[i].flags = items[i].flags;
        g_tray_items[i].label = items[i].label ? strdup(items[i].label) : strdup("");
        if (!g_tray_items[i].label) {
            free_tray_items();
            return 0;
        }
    }
    g_n_tray = n;
    if (g_tray_revision == 0xFFFFFFFFu)
        g_tray_revision = 1;
    else
        g_tray_revision++;
    emit_layout_updated(ZTRAY_TRAY_MENU_PATH, g_tray_revision);
    return 1;
}

int ztray_linux_tray_install(const char *tooltip_utf8, const char *icon_name_or_null) {
    if (ztray_linux_dbus_init() == 0) return 0;

    free(g_tray_tooltip);
    g_tray_tooltip = tooltip_utf8 ? strdup(tooltip_utf8) : strdup("ztray");
    if (!g_tray_tooltip) return 0;

    free(g_tray_icon_name);
    if (icon_name_or_null && icon_name_or_null[0])
        g_tray_icon_name = strdup(icon_name_or_null);
    else
        g_tray_icon_name = NULL;

    g_tray_sni_active = 1;
    (void)register_sni_watcher();
    return 1;
}

void ztray_linux_tray_shutdown(void) {
    g_tray_sni_active = 0;
    free(g_tray_tooltip);
    g_tray_tooltip = NULL;
    free(g_tray_icon_name);
    g_tray_icon_name = NULL;
    free_tray_items();
    g_tray_revision = 0;
    atomic_store(&g_pending_tray_action, -1);
}

void ztray_linux_dbus_dispatch(void) {
    if (g_conn) dbus_connection_read_write_dispatch(g_conn, 0);
}

int ztray_linux_dbus_take_pending(void) {
    return atomic_exchange(&g_pending_menubar_action, -1);
}

int ztray_linux_tray_take_pending(void) {
    return atomic_exchange(&g_pending_tray_action, -1);
}
