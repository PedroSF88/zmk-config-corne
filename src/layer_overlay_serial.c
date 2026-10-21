#include <zephyr/device.h>
#include <zephyr/drivers/uart.h>
#include <zephyr/init.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>

#include <zmk/event_manager.h>
#include <zmk/events/layer_state_changed.h>
#include <zmk/events/usb_conn_state_changed.h>
#include <zmk/keymap.h>
#include <zmk/usb.h>

#define OVERLAY_UART_NODE DT_CHOSEN(zmk_studio_rpc_uart)

#if !DT_HAS_CHOSEN(zmk_studio_rpc_uart)
#error "CONFIG_ZMK_LAYER_OVERLAY_SERIAL requires the zmk,studio-rpc-uart chosen node."
#endif

static const struct device *const overlay_uart = DEVICE_DT_GET(OVERLAY_UART_NODE);
static int last_sent_layer = -1;

static void overlay_uart_write(const char *msg) {
    for (const char *c = msg; *c != '\0'; c++) {
        uart_poll_out(overlay_uart, (unsigned char)*c);
    }
}

static void send_active_layer(bool force) {
    if (!device_is_ready(overlay_uart) || !zmk_usb_is_powered()) {
        return;
    }

    zmk_keymap_layer_index_t index = zmk_keymap_highest_layer_active();
    if (!force && last_sent_layer == (int)index) {
        return;
    }

    last_sent_layer = (int)index;

    const char *layer_name = zmk_keymap_layer_name(zmk_keymap_layer_index_to_id(index));
    char line[96];

    snprintk(line, sizeof(line), "ZMK_OVERLAY|LAYER|%u|%s\n", index,
             layer_name != NULL ? layer_name : "");
    overlay_uart_write(line);
}

static int layer_overlay_listener(const zmk_event_t *eh) {
    const struct zmk_layer_state_changed *layer_ev = as_zmk_layer_state_changed(eh);
    if (layer_ev != NULL) {
        ARG_UNUSED(layer_ev);
        send_active_layer(false);
        return ZMK_EV_EVENT_BUBBLE;
    }

    const struct zmk_usb_conn_state_changed *usb_ev = as_zmk_usb_conn_state_changed(eh);
    if (usb_ev != NULL && usb_ev->conn_state != ZMK_USB_CONN_NONE) {
        send_active_layer(true);
    }

    return ZMK_EV_EVENT_BUBBLE;
}

static int layer_overlay_init(void) {
    if (!device_is_ready(overlay_uart)) {
        return -ENODEV;
    }

    return 0;
}

SYS_INIT(layer_overlay_init, APPLICATION, CONFIG_APPLICATION_INIT_PRIORITY);

ZMK_LISTENER(layer_overlay_serial, layer_overlay_listener);
ZMK_SUBSCRIPTION(layer_overlay_serial, zmk_layer_state_changed);
ZMK_SUBSCRIPTION(layer_overlay_serial, zmk_usb_conn_state_changed);
