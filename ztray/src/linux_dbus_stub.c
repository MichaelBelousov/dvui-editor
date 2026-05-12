/* No-op DBus menu: used when cross-compiling for Linux from a non-Linux host (no libdbus headers). */
#include <stdint.h>

typedef struct {
    int32_t id;
    int32_t parent_id;
    int32_t action_id;
    uint32_t flags;
    const char *label;
} ZTrayLinuxItem;

int ztray_linux_dbus_init(void) { return 1; }
void ztray_linux_dbus_shutdown(void) {}
int ztray_linux_dbus_set_items(const ZTrayLinuxItem *items, int n) {
    (void)items;
    (void)n;
    return 1;
}
void ztray_linux_dbus_dispatch(void) {}
int ztray_linux_dbus_take_pending(void) { return -1; }
