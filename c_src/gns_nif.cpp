#include <erl_nif.h>
#include <string.h>
#include <stdlib.h>
#include <pthread.h>

// GNS headers (C++ lib with extern "C" flat API)
#include "steamnetworkingtypes.h"
#include "steamnetworkingsockets.h"
#include "steamnetworkingsockets_flat.h"
#include "isteamnetworkingutils.h"

// Steamworks SDK types (relay tickets, hosted addresses, game coordinator)
// Define HAS_STEAM_DATAGRAM_TYPES when building against the full Steamworks SDK.
#ifdef HAS_STEAM_DATAGRAM_TYPES
#include "steamdatagram_tickets.h"
#endif

// ---------------------------------------------------------------------------
// Connection status event queue (thread-safe ring buffer)
// ---------------------------------------------------------------------------

#define EVENT_QUEUE_CAPACITY 4096
#define DEBUG_QUEUE_CAPACITY 1024

typedef struct {
    uint32_t conn;
    int old_state;
    int new_state;
    int end_reason;
    char end_debug[128];
} gns_connection_event_t;

static gns_connection_event_t g_event_queue[EVENT_QUEUE_CAPACITY];
static volatile int g_event_head = 0;  // write position
static volatile int g_event_tail = 0;  // read position
static pthread_mutex_t g_event_mutex = PTHREAD_MUTEX_INITIALIZER;

static void event_queue_push(const gns_connection_event_t *event) {
    pthread_mutex_lock(&g_event_mutex);
    int next = (g_event_head + 1) % EVENT_QUEUE_CAPACITY;
    if (next != g_event_tail) {
        g_event_queue[g_event_head] = *event;
        g_event_head = next;
    }
    // else: queue full, drop event
    pthread_mutex_unlock(&g_event_mutex);
}

static int event_queue_pop(gns_connection_event_t *event) {
    pthread_mutex_lock(&g_event_mutex);
    if (g_event_tail == g_event_head) {
        pthread_mutex_unlock(&g_event_mutex);
        return 0;
    }
    *event = g_event_queue[g_event_tail];
    g_event_tail = (g_event_tail + 1) % EVENT_QUEUE_CAPACITY;
    pthread_mutex_unlock(&g_event_mutex);
    return 1;
}

// ---------------------------------------------------------------------------
// Debug output message queue (thread-safe ring buffer)
// ---------------------------------------------------------------------------

typedef struct {
    int type;
    char msg[512];
} gns_debug_message_t;

static gns_debug_message_t g_debug_queue[DEBUG_QUEUE_CAPACITY];
static volatile int g_debug_head = 0;
static volatile int g_debug_tail = 0;
static pthread_mutex_t g_debug_mutex = PTHREAD_MUTEX_INITIALIZER;

static void debug_queue_push(const gns_debug_message_t *msg) {
    pthread_mutex_lock(&g_debug_mutex);
    int next = (g_debug_head + 1) % DEBUG_QUEUE_CAPACITY;
    if (next != g_debug_tail) {
        g_debug_queue[g_debug_head] = *msg;
        g_debug_head = next;
    }
    pthread_mutex_unlock(&g_debug_mutex);
}

static int debug_queue_pop(gns_debug_message_t *msg) {
    pthread_mutex_lock(&g_debug_mutex);
    if (g_debug_tail == g_debug_head) {
        pthread_mutex_unlock(&g_debug_mutex);
        return 0;
    }
    *msg = g_debug_queue[g_debug_tail];
    g_debug_tail = (g_debug_tail + 1) % DEBUG_QUEUE_CAPACITY;
    pthread_mutex_unlock(&g_debug_mutex);
    return 1;
}

static void on_debug_output(ESteamNetworkingSocketsDebugOutputType type, const char *pszMsg) {
    gns_debug_message_t msg;
    msg.type = (int)type;
    strncpy(msg.msg, pszMsg, sizeof(msg.msg) - 1);
    msg.msg[sizeof(msg.msg) - 1] = '\0';
    debug_queue_push(&msg);
}

// ---------------------------------------------------------------------------
// Global connection status changed callback
// ---------------------------------------------------------------------------

static void on_connection_status_changed(SteamNetConnectionStatusChangedCallback_t *info) {
    gns_connection_event_t event;
    event.conn = info->m_hConn;
    event.old_state = (int)info->m_eOldState;
    event.new_state = (int)info->m_info.m_eState;
    event.end_reason = (int)info->m_info.m_eEndReason;
    strncpy(event.end_debug, info->m_info.m_szEndDebug, sizeof(event.end_debug) - 1);
    event.end_debug[sizeof(event.end_debug) - 1] = '\0';
    event_queue_push(&event);
}

// ---------------------------------------------------------------------------
// Helper: get interface singletons
// ---------------------------------------------------------------------------

static ISteamNetworkingSockets *get_interface(void) {
    return SteamAPI_SteamNetworkingSockets_v009();
}

static ISteamNetworkingUtils *get_utils(void) {
    return SteamAPI_SteamNetworkingUtils_v003();
}

// ---------------------------------------------------------------------------
// Helper: parse "ip:port" or just ip + port into SteamNetworkingIPAddr
// ---------------------------------------------------------------------------

static int parse_ip_port(ErlNifEnv *env, ERL_NIF_TERM ip_term, ERL_NIF_TERM port_term,
                         SteamNetworkingIPAddr *addr) {
    char ip_str[256];
    unsigned int port;

    if (!enif_get_string(env, ip_term, ip_str, sizeof(ip_str), ERL_NIF_LATIN1))
        return 0;
    if (!enif_get_uint(env, port_term, &port))
        return 0;

    SteamAPI_SteamNetworkingIPAddr_Clear(addr);
    // Try parsing the string (handles both IPv4 and IPv6)
    if (!SteamAPI_SteamNetworkingIPAddr_ParseString(addr, ip_str)) {
        return 0;
    }
    addr->m_port = (uint16_t)port;
    return 1;
}

// ---------------------------------------------------------------------------
// Atom helpers
// ---------------------------------------------------------------------------

static ERL_NIF_TERM atom_ok;
static ERL_NIF_TERM atom_error;
static ERL_NIF_TERM atom_true;
static ERL_NIF_TERM atom_false;

// Map key atoms for connection events
static ERL_NIF_TERM atom_conn;
static ERL_NIF_TERM atom_old_state;
static ERL_NIF_TERM atom_new_state;
static ERL_NIF_TERM atom_end_reason;
static ERL_NIF_TERM atom_end_debug;

// Map key atoms for connection info
static ERL_NIF_TERM atom_state;
static ERL_NIF_TERM atom_listen_socket;
static ERL_NIF_TERM atom_remote_address;
static ERL_NIF_TERM atom_remote_port;
static ERL_NIF_TERM atom_user_data;
static ERL_NIF_TERM atom_flags;
static ERL_NIF_TERM atom_connection_description;

// Map key atoms for real-time status
static ERL_NIF_TERM atom_ping;
static ERL_NIF_TERM atom_quality_local;
static ERL_NIF_TERM atom_quality_remote;
static ERL_NIF_TERM atom_out_packets_per_sec;
static ERL_NIF_TERM atom_out_bytes_per_sec;
static ERL_NIF_TERM atom_in_packets_per_sec;
static ERL_NIF_TERM atom_in_bytes_per_sec;
static ERL_NIF_TERM atom_send_rate_bytes_per_sec;
static ERL_NIF_TERM atom_pending_unreliable;
static ERL_NIF_TERM atom_pending_reliable;
static ERL_NIF_TERM atom_sent_unacked_reliable;
static ERL_NIF_TERM atom_queue_time_usec;

// Map key atoms for messages
static ERL_NIF_TERM atom_payload;
static ERL_NIF_TERM atom_message_number;
static ERL_NIF_TERM atom_channel;
static ERL_NIF_TERM atom_lane;
static ERL_NIF_TERM atom_conn_user_data;

// Map key atoms for debug messages
static ERL_NIF_TERM atom_type;
static ERL_NIF_TERM atom_msg;

// Map key atoms for listen socket address
static ERL_NIF_TERM atom_address;
static ERL_NIF_TERM atom_port;

// Map key atoms for auth/relay status
static ERL_NIF_TERM atom_availability;
static ERL_NIF_TERM atom_debug_msg;
static ERL_NIF_TERM atom_ping_in_progress;
static ERL_NIF_TERM atom_network_config;
static ERL_NIF_TERM atom_any_relay;

// Send flag atoms
static ERL_NIF_TERM atom_send_unreliable;
static ERL_NIF_TERM atom_send_reliable;
static ERL_NIF_TERM atom_send_no_nagle;
static ERL_NIF_TERM atom_send_no_delay;

// ---------------------------------------------------------------------------
// NIF: gns_init/0
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_gns_init(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    SteamNetworkingErrMsg err_msg;
    memset(err_msg, 0, sizeof(err_msg));

    if (!GameNetworkingSockets_Init(NULL, err_msg)) {
        return enif_make_tuple2(env, atom_error,
            enif_make_string(env, (const char *)err_msg, ERL_NIF_LATIN1));
    }

    // Register global callback for connection status changes
    ISteamNetworkingUtils *utils = get_utils();
    SteamAPI_ISteamNetworkingUtils_SetGlobalCallback_SteamNetConnectionStatusChanged(
        utils, on_connection_status_changed);

    return atom_ok;
}

// ---------------------------------------------------------------------------
// NIF: gns_kill/0
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_gns_kill(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    GameNetworkingSockets_Kill();
    return atom_ok;
}

// ---------------------------------------------------------------------------
// NIF: poll_callbacks/0
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_poll_callbacks(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    SteamAPI_ISteamNetworkingSockets_RunCallbacks(get_interface());
    return atom_ok;
}

// ---------------------------------------------------------------------------
// NIF: poll_connection_status_changes/1 (max_events)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_poll_connection_status_changes(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int max_events;
    if (!enif_get_uint(env, argv[0], &max_events))
        return enif_make_badarg(env);

    ERL_NIF_TERM list = enif_make_list(env, 0);
    gns_connection_event_t event;
    unsigned int count = 0;

    // Collect events into a temporary array so we can build the list in order
    gns_connection_event_t events[256];
    unsigned int cap = max_events < 256 ? max_events : 256;

    while (count < cap && event_queue_pop(&event)) {
        events[count++] = event;
    }

    // Build list in reverse (since we prepend)
    for (int i = (int)count - 1; i >= 0; i--) {
        ERL_NIF_TERM keys[] = { atom_conn, atom_old_state, atom_new_state, atom_end_reason, atom_end_debug };
        ERL_NIF_TERM vals[] = {
            enif_make_uint(env, events[i].conn),
            enif_make_int(env, events[i].old_state),
            enif_make_int(env, events[i].new_state),
            enif_make_int(env, events[i].end_reason),
            enif_make_string(env, events[i].end_debug, ERL_NIF_LATIN1)
        };
        ERL_NIF_TERM map;
        enif_make_map_from_arrays(env, keys, vals, 5, &map);
        list = enif_make_list_cell(env, map, list);
    }

    return list;
}

// ---------------------------------------------------------------------------
// NIF: create_listen_socket_ip/2 (ip_string, port)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_create_listen_socket_ip(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    SteamNetworkingIPAddr addr;
    if (!parse_ip_port(env, argv[0], argv[1], &addr))
        return enif_make_badarg(env);

    HSteamListenSocket sock = SteamAPI_ISteamNetworkingSockets_CreateListenSocketIP(
        get_interface(), addr, 0, NULL);

    if (sock == k_HSteamListenSocket_Invalid)
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "invalid_socket"));

    return enif_make_tuple2(env, atom_ok, enif_make_uint(env, sock));
}

// ---------------------------------------------------------------------------
// NIF: connect_by_ip_address/2 (ip_string, port)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_connect_by_ip_address(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    SteamNetworkingIPAddr addr;
    if (!parse_ip_port(env, argv[0], argv[1], &addr))
        return enif_make_badarg(env);

    HSteamNetConnection conn = SteamAPI_ISteamNetworkingSockets_ConnectByIPAddress(
        get_interface(), addr, 0, NULL);

    if (conn == k_HSteamNetConnection_Invalid)
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "invalid_connection"));

    return enif_make_tuple2(env, atom_ok, enif_make_uint(env, conn));
}

// ---------------------------------------------------------------------------
// NIF: accept_connection/1 (conn_handle)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_accept_connection(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int conn;
    if (!enif_get_uint(env, argv[0], &conn))
        return enif_make_badarg(env);

    EResult result = SteamAPI_ISteamNetworkingSockets_AcceptConnection(get_interface(), conn);
    if (result == k_EResultOK)
        return atom_ok;

    return enif_make_tuple2(env, atom_error, enif_make_int(env, (int)result));
}

// ---------------------------------------------------------------------------
// NIF: close_connection/4 (conn, reason, debug_string, linger_bool)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_close_connection(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int conn;
    int reason;
    char debug[256];
    char linger_str[6]; // "true" or "false"

    if (!enif_get_uint(env, argv[0], &conn))
        return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &reason))
        return enif_make_badarg(env);
    if (!enif_get_string(env, argv[2], debug, sizeof(debug), ERL_NIF_LATIN1))
        return enif_make_badarg(env);
    if (!enif_get_atom(env, argv[3], linger_str, sizeof(linger_str), ERL_NIF_LATIN1))
        return enif_make_badarg(env);

    bool linger = (strcmp(linger_str, "true") == 0);

    bool ok = SteamAPI_ISteamNetworkingSockets_CloseConnection(
        get_interface(), conn, reason, debug, linger);

    return ok ? atom_true : atom_false;
}

// ---------------------------------------------------------------------------
// NIF: close_listen_socket/1 (socket_handle)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_close_listen_socket(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int sock;
    if (!enif_get_uint(env, argv[0], &sock))
        return enif_make_badarg(env);

    bool ok = SteamAPI_ISteamNetworkingSockets_CloseListenSocket(get_interface(), sock);
    return ok ? atom_true : atom_false;
}

// ---------------------------------------------------------------------------
// NIF: create_poll_group/0
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_create_poll_group(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    HSteamNetPollGroup pg = SteamAPI_ISteamNetworkingSockets_CreatePollGroup(get_interface());
    if (pg == k_HSteamNetPollGroup_Invalid)
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "invalid_poll_group"));

    return enif_make_tuple2(env, atom_ok, enif_make_uint(env, pg));
}

// ---------------------------------------------------------------------------
// NIF: destroy_poll_group/1 (poll_group)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_destroy_poll_group(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int pg;
    if (!enif_get_uint(env, argv[0], &pg))
        return enif_make_badarg(env);

    bool ok = SteamAPI_ISteamNetworkingSockets_DestroyPollGroup(get_interface(), pg);
    return ok ? atom_true : atom_false;
}

// ---------------------------------------------------------------------------
// NIF: set_connection_poll_group/2 (conn, poll_group)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_set_connection_poll_group(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int conn, pg;
    if (!enif_get_uint(env, argv[0], &conn))
        return enif_make_badarg(env);
    if (!enif_get_uint(env, argv[1], &pg))
        return enif_make_badarg(env);

    bool ok = SteamAPI_ISteamNetworkingSockets_SetConnectionPollGroup(get_interface(), conn, pg);
    return ok ? atom_true : atom_false;
}

// ---------------------------------------------------------------------------
// NIF: send_message_to_connection/3 (conn, binary_data, send_flags)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_send_message_to_connection(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int conn;
    ErlNifBinary bin;
    int send_flags;

    if (!enif_get_uint(env, argv[0], &conn))
        return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[1], &bin))
        return enif_make_badarg(env);
    if (!enif_get_int(env, argv[2], &send_flags))
        return enif_make_badarg(env);

    int64 out_msg_num = 0;
    EResult result = SteamAPI_ISteamNetworkingSockets_SendMessageToConnection(
        get_interface(), conn, bin.data, (uint32_t)bin.size, send_flags, &out_msg_num);

    if (result == k_EResultOK)
        return enif_make_tuple2(env, atom_ok, enif_make_int64(env, out_msg_num));

    return enif_make_tuple2(env, atom_error, enif_make_int(env, (int)result));
}

// ---------------------------------------------------------------------------
// NIF: flush_messages_on_connection/1 (conn)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_flush_messages_on_connection(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int conn;
    if (!enif_get_uint(env, argv[0], &conn))
        return enif_make_badarg(env);

    EResult result = SteamAPI_ISteamNetworkingSockets_FlushMessagesOnConnection(get_interface(), conn);
    if (result == k_EResultOK)
        return atom_ok;

    return enif_make_tuple2(env, atom_error, enif_make_int(env, (int)result));
}

// ---------------------------------------------------------------------------
// Helper: convert a received SteamNetworkingMessage_t to an Erlang map
// ---------------------------------------------------------------------------

static ERL_NIF_TERM message_to_map(ErlNifEnv *env, SteamNetworkingMessage_t *msg) {
    // Copy payload into a binary
    ERL_NIF_TERM payload_bin;
    unsigned char *buf = enif_make_new_binary(env, msg->m_cbSize, &payload_bin);
    memcpy(buf, msg->m_pData, msg->m_cbSize);

    ERL_NIF_TERM keys[] = {
        atom_conn, atom_payload, atom_message_number,
        atom_flags, atom_lane, atom_conn_user_data
    };
    ERL_NIF_TERM vals[] = {
        enif_make_uint(env, msg->m_conn),
        payload_bin,
        enif_make_int64(env, msg->m_nMessageNumber),
        enif_make_int(env, msg->m_nFlags),
        enif_make_uint(env, msg->m_idxLane),
        enif_make_int64(env, msg->m_nConnUserData)
    };

    ERL_NIF_TERM map;
    enif_make_map_from_arrays(env, keys, vals, 6, &map);
    return map;
}

// ---------------------------------------------------------------------------
// NIF: receive_messages_on_connection/2 (conn, max_messages)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_receive_messages_on_connection(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int conn, max_messages;
    if (!enif_get_uint(env, argv[0], &conn))
        return enif_make_badarg(env);
    if (!enif_get_uint(env, argv[1], &max_messages))
        return enif_make_badarg(env);

    if (max_messages > 256) max_messages = 256;

    SteamNetworkingMessage_t *messages[256];
    int count = SteamAPI_ISteamNetworkingSockets_ReceiveMessagesOnConnection(
        get_interface(), conn, messages, (int)max_messages);

    if (count < 0)
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "invalid_connection"));

    ERL_NIF_TERM list = enif_make_list(env, 0);
    for (int i = count - 1; i >= 0; i--) {
        ERL_NIF_TERM msg_map = message_to_map(env, messages[i]);
        list = enif_make_list_cell(env, msg_map, list);
        SteamAPI_SteamNetworkingMessage_t_Release(messages[i]);
    }

    return list;
}

// ---------------------------------------------------------------------------
// NIF: receive_messages_on_poll_group/2 (poll_group, max_messages)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_receive_messages_on_poll_group(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int pg, max_messages;
    if (!enif_get_uint(env, argv[0], &pg))
        return enif_make_badarg(env);
    if (!enif_get_uint(env, argv[1], &max_messages))
        return enif_make_badarg(env);

    if (max_messages > 256) max_messages = 256;

    SteamNetworkingMessage_t *messages[256];
    int count = SteamAPI_ISteamNetworkingSockets_ReceiveMessagesOnPollGroup(
        get_interface(), pg, messages, (int)max_messages);

    if (count < 0)
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "invalid_poll_group"));

    ERL_NIF_TERM list = enif_make_list(env, 0);
    for (int i = count - 1; i >= 0; i--) {
        ERL_NIF_TERM msg_map = message_to_map(env, messages[i]);
        list = enif_make_list_cell(env, msg_map, list);
        SteamAPI_SteamNetworkingMessage_t_Release(messages[i]);
    }

    return list;
}

// ---------------------------------------------------------------------------
// NIF: get_connection_info/1 (conn)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_get_connection_info(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int conn;
    if (!enif_get_uint(env, argv[0], &conn))
        return enif_make_badarg(env);

    SteamNetConnectionInfo_t info;
    if (!SteamAPI_ISteamNetworkingSockets_GetConnectionInfo(get_interface(), conn, &info))
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "invalid_connection"));

    // Format remote address as string
    char addr_str[SteamNetworkingIPAddr::k_cchMaxString];
    SteamAPI_SteamNetworkingIPAddr_ToString(&info.m_addrRemote, addr_str, sizeof(addr_str), false);

    ERL_NIF_TERM keys[] = {
        atom_state, atom_end_reason, atom_end_debug,
        atom_remote_address, atom_remote_port,
        atom_user_data, atom_listen_socket, atom_flags,
        atom_connection_description
    };
    ERL_NIF_TERM vals[] = {
        enif_make_int(env, (int)info.m_eState),
        enif_make_int(env, (int)info.m_eEndReason),
        enif_make_string(env, info.m_szEndDebug, ERL_NIF_LATIN1),
        enif_make_string(env, addr_str, ERL_NIF_LATIN1),
        enif_make_uint(env, info.m_addrRemote.m_port),
        enif_make_int64(env, info.m_nUserData),
        enif_make_uint(env, info.m_hListenSocket),
        enif_make_int(env, info.m_nFlags),
        enif_make_string(env, info.m_szConnectionDescription, ERL_NIF_LATIN1)
    };

    ERL_NIF_TERM map;
    enif_make_map_from_arrays(env, keys, vals, 9, &map);
    return enif_make_tuple2(env, atom_ok, map);
}

// ---------------------------------------------------------------------------
// NIF: get_connection_real_time_status/2 (conn, num_lanes)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_get_connection_real_time_status(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int conn, num_lanes;
    if (!enif_get_uint(env, argv[0], &conn))
        return enif_make_badarg(env);
    if (!enif_get_uint(env, argv[1], &num_lanes))
        return enif_make_badarg(env);

    SteamNetConnectionRealTimeStatus_t status;
    SteamNetConnectionRealTimeLaneStatus_t lanes[16];
    if (num_lanes > 16) num_lanes = 16;

    EResult result = SteamAPI_ISteamNetworkingSockets_GetConnectionRealTimeStatus(
        get_interface(), conn, &status, (int)num_lanes, num_lanes > 0 ? lanes : NULL);

    if (result != k_EResultOK)
        return enif_make_tuple2(env, atom_error, enif_make_int(env, (int)result));

    ERL_NIF_TERM keys[] = {
        atom_state, atom_ping, atom_quality_local, atom_quality_remote,
        atom_out_packets_per_sec, atom_out_bytes_per_sec,
        atom_in_packets_per_sec, atom_in_bytes_per_sec,
        atom_send_rate_bytes_per_sec,
        atom_pending_unreliable, atom_pending_reliable,
        atom_sent_unacked_reliable, atom_queue_time_usec
    };
    ERL_NIF_TERM vals[] = {
        enif_make_int(env, (int)status.m_eState),
        enif_make_int(env, status.m_nPing),
        enif_make_double(env, (double)status.m_flConnectionQualityLocal),
        enif_make_double(env, (double)status.m_flConnectionQualityRemote),
        enif_make_double(env, (double)status.m_flOutPacketsPerSec),
        enif_make_double(env, (double)status.m_flOutBytesPerSec),
        enif_make_double(env, (double)status.m_flInPacketsPerSec),
        enif_make_double(env, (double)status.m_flInBytesPerSec),
        enif_make_int(env, status.m_nSendRateBytesPerSecond),
        enif_make_int(env, status.m_cbPendingUnreliable),
        enif_make_int(env, status.m_cbPendingReliable),
        enif_make_int(env, status.m_cbSentUnackedReliable),
        enif_make_int64(env, status.m_usecQueueTime)
    };

    ERL_NIF_TERM status_map;
    enif_make_map_from_arrays(env, keys, vals, 13, &status_map);

    // Build lanes list
    ERL_NIF_TERM lanes_list = enif_make_list(env, 0);
    for (int i = (int)num_lanes - 1; i >= 0; i--) {
        ERL_NIF_TERM lkeys[] = {
            atom_pending_unreliable, atom_pending_reliable,
            atom_sent_unacked_reliable, atom_queue_time_usec
        };
        ERL_NIF_TERM lvals[] = {
            enif_make_int(env, lanes[i].m_cbPendingUnreliable),
            enif_make_int(env, lanes[i].m_cbPendingReliable),
            enif_make_int(env, lanes[i].m_cbSentUnackedReliable),
            enif_make_int64(env, lanes[i].m_usecQueueTime)
        };
        ERL_NIF_TERM lane_map;
        enif_make_map_from_arrays(env, lkeys, lvals, 4, &lane_map);
        lanes_list = enif_make_list_cell(env, lane_map, lanes_list);
    }

    return enif_make_tuple3(env, atom_ok, status_map, lanes_list);
}

// ---------------------------------------------------------------------------
// NIF: set_connection_user_data/2 (conn, user_data_int64)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_set_connection_user_data(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int conn;
    ErlNifSInt64 user_data;
    if (!enif_get_uint(env, argv[0], &conn))
        return enif_make_badarg(env);
    if (!enif_get_int64(env, argv[1], &user_data))
        return enif_make_badarg(env);

    bool ok = SteamAPI_ISteamNetworkingSockets_SetConnectionUserData(get_interface(), conn, user_data);
    return ok ? atom_true : atom_false;
}

// ---------------------------------------------------------------------------
// NIF: configure_connection_lanes/3 (conn, priorities_list, weights_list)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_configure_connection_lanes(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int conn;
    if (!enif_get_uint(env, argv[0], &conn))
        return enif_make_badarg(env);

    unsigned int prio_len, weight_len;
    if (!enif_get_list_length(env, argv[1], &prio_len))
        return enif_make_badarg(env);
    if (!enif_get_list_length(env, argv[2], &weight_len))
        return enif_make_badarg(env);
    if (prio_len != weight_len || prio_len > 256)
        return enif_make_badarg(env);

    int priorities[256];
    uint16_t weights[256];

    ERL_NIF_TERM head, tail;
    tail = argv[1];
    for (unsigned int i = 0; i < prio_len; i++) {
        enif_get_list_cell(env, tail, &head, &tail);
        int val;
        if (!enif_get_int(env, head, &val)) return enif_make_badarg(env);
        priorities[i] = val;
    }

    tail = argv[2];
    for (unsigned int i = 0; i < weight_len; i++) {
        enif_get_list_cell(env, tail, &head, &tail);
        unsigned int val;
        if (!enif_get_uint(env, head, &val)) return enif_make_badarg(env);
        weights[i] = (uint16_t)val;
    }

    EResult result = SteamAPI_ISteamNetworkingSockets_ConfigureConnectionLanes(
        get_interface(), conn, (int)prio_len, priorities, weights);

    if (result == k_EResultOK)
        return atom_ok;

    return enif_make_tuple2(env, atom_error, enif_make_int(env, (int)result));
}

// ---------------------------------------------------------------------------
// NIF: get_connection_user_data/1 (conn)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_get_connection_user_data(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int conn;
    if (!enif_get_uint(env, argv[0], &conn))
        return enif_make_badarg(env);

    int64 user_data = SteamAPI_ISteamNetworkingSockets_GetConnectionUserData(get_interface(), conn);
    return enif_make_int64(env, user_data);
}

// ---------------------------------------------------------------------------
// NIF: get_detailed_connection_status/1 (conn)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_get_detailed_connection_status(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int conn;
    if (!enif_get_uint(env, argv[0], &conn))
        return enif_make_badarg(env);

    char buf[4096];
    int result = SteamAPI_ISteamNetworkingSockets_GetDetailedConnectionStatus(
        get_interface(), conn, buf, sizeof(buf));

    if (result < 0)
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "invalid_connection"));

    return enif_make_tuple2(env, atom_ok, enif_make_string(env, buf, ERL_NIF_LATIN1));
}

// ---------------------------------------------------------------------------
// NIF: get_listen_socket_address/1 (socket_handle)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_get_listen_socket_address(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int sock;
    if (!enif_get_uint(env, argv[0], &sock))
        return enif_make_badarg(env);

    SteamNetworkingIPAddr addr;
    if (!SteamAPI_ISteamNetworkingSockets_GetListenSocketAddress(get_interface(), sock, &addr))
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "failed"));

    char addr_str[SteamNetworkingIPAddr::k_cchMaxString];
    SteamAPI_SteamNetworkingIPAddr_ToString(&addr, addr_str, sizeof(addr_str), false);

    ERL_NIF_TERM keys[] = { atom_address, atom_port };
    ERL_NIF_TERM vals[] = {
        enif_make_string(env, addr_str, ERL_NIF_LATIN1),
        enif_make_uint(env, addr.m_port)
    };
    ERL_NIF_TERM map;
    enif_make_map_from_arrays(env, keys, vals, 2, &map);
    return enif_make_tuple2(env, atom_ok, map);
}

// ---------------------------------------------------------------------------
// NIF: set_connection_name/2 (conn, name_string)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_set_connection_name(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int conn;
    char name[256];
    if (!enif_get_uint(env, argv[0], &conn))
        return enif_make_badarg(env);
    if (!enif_get_string(env, argv[1], name, sizeof(name), ERL_NIF_LATIN1))
        return enif_make_badarg(env);

    SteamAPI_ISteamNetworkingSockets_SetConnectionName(get_interface(), conn, name);
    return atom_ok;
}

// ---------------------------------------------------------------------------
// NIF: get_connection_name/1 (conn)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_get_connection_name(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int conn;
    if (!enif_get_uint(env, argv[0], &conn))
        return enif_make_badarg(env);

    char name[256];
    if (!SteamAPI_ISteamNetworkingSockets_GetConnectionName(get_interface(), conn, name, sizeof(name)))
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "invalid_connection"));

    return enif_make_tuple2(env, atom_ok, enif_make_string(env, name, ERL_NIF_LATIN1));
}

// ---------------------------------------------------------------------------
// NIF: send_messages/1 (list of {conn, binary, flags} or {conn, binary, flags, lane})
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_send_messages(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int count;
    if (!enif_get_list_length(env, argv[0], &count))
        return enif_make_badarg(env);
    if (count == 0)
        return enif_make_list(env, 0);
    if (count > 256) count = 256;

    SteamNetworkingMessage_t *messages[256];
    ISteamNetworkingUtils *utils = get_utils();

    ERL_NIF_TERM head, tail = argv[0];
    for (unsigned int i = 0; i < count; i++) {
        enif_get_list_cell(env, tail, &head, &tail);

        int arity;
        const ERL_NIF_TERM *tuple;
        if (!enif_get_tuple(env, head, &arity, &tuple) || (arity != 3 && arity != 4)) {
            // Free already-allocated messages
            for (unsigned int j = 0; j < i; j++)
                SteamAPI_SteamNetworkingMessage_t_Release(messages[j]);
            return enif_make_badarg(env);
        }

        unsigned int conn;
        ErlNifBinary bin;
        int flags;
        unsigned int lane = 0;

        if (!enif_get_uint(env, tuple[0], &conn) ||
            !enif_inspect_binary(env, tuple[1], &bin) ||
            !enif_get_int(env, tuple[2], &flags)) {
            for (unsigned int j = 0; j < i; j++)
                SteamAPI_SteamNetworkingMessage_t_Release(messages[j]);
            return enif_make_badarg(env);
        }
        if (arity == 4 && !enif_get_uint(env, tuple[3], &lane)) {
            for (unsigned int j = 0; j < i; j++)
                SteamAPI_SteamNetworkingMessage_t_Release(messages[j]);
            return enif_make_badarg(env);
        }

        SteamNetworkingMessage_t *msg = SteamAPI_ISteamNetworkingUtils_AllocateMessage(utils, (int)bin.size);
        if (!msg) {
            for (unsigned int j = 0; j < i; j++)
                SteamAPI_SteamNetworkingMessage_t_Release(messages[j]);
            return enif_make_tuple2(env, atom_error, enif_make_atom(env, "allocation_failed"));
        }

        memcpy(msg->m_pData, bin.data, bin.size);
        msg->m_conn = conn;
        msg->m_nFlags = flags;
        msg->m_idxLane = (uint16_t)lane;

        messages[i] = msg;
    }

    int64 results[256];
    SteamAPI_ISteamNetworkingSockets_SendMessages(get_interface(), (int)count, messages, results);

    // Build result list (SendMessages takes ownership of messages, do not release)
    ERL_NIF_TERM list = enif_make_list(env, 0);
    for (int i = (int)count - 1; i >= 0; i--) {
        ERL_NIF_TERM result;
        if (results[i] > 0)
            result = enif_make_tuple2(env, atom_ok, enif_make_int64(env, results[i]));
        else
            result = enif_make_tuple2(env, atom_error, enif_make_int64(env, results[i]));
        list = enif_make_list_cell(env, result, list);
    }

    return list;
}

// ---------------------------------------------------------------------------
// NIF: set_debug_output_level/1 (detail_level_int)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_set_debug_output_level(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    int level;
    if (!enif_get_int(env, argv[0], &level))
        return enif_make_badarg(env);

    SteamAPI_ISteamNetworkingUtils_SetDebugOutputFunction(
        get_utils(), (ESteamNetworkingSocketsDebugOutputType)level, on_debug_output);

    return atom_ok;
}

// ---------------------------------------------------------------------------
// NIF: poll_debug_messages/1 (max_messages)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_poll_debug_messages(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int max_messages;
    if (!enif_get_uint(env, argv[0], &max_messages))
        return enif_make_badarg(env);

    gns_debug_message_t messages_buf[256];
    unsigned int cap = max_messages < 256 ? max_messages : 256;
    unsigned int count = 0;
    gns_debug_message_t dmsg;

    while (count < cap && debug_queue_pop(&dmsg)) {
        messages_buf[count++] = dmsg;
    }

    ERL_NIF_TERM list = enif_make_list(env, 0);
    for (int i = (int)count - 1; i >= 0; i--) {
        ERL_NIF_TERM keys[] = { atom_type, atom_msg };
        ERL_NIF_TERM vals[] = {
            enif_make_int(env, messages_buf[i].type),
            enif_make_string(env, messages_buf[i].msg, ERL_NIF_LATIN1)
        };
        ERL_NIF_TERM map;
        enif_make_map_from_arrays(env, keys, vals, 2, &map);
        list = enif_make_list_cell(env, map, list);
    }

    return list;
}

// ---------------------------------------------------------------------------
// NIF: set_global_config_int/2 (config_key, int_value)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_set_global_config_int(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    int config_key, value;
    if (!enif_get_int(env, argv[0], &config_key))
        return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &value))
        return enif_make_badarg(env);

    bool ok = SteamAPI_ISteamNetworkingUtils_SetConfigValue(
        get_utils(),
        (ESteamNetworkingConfigValue)config_key,
        k_ESteamNetworkingConfig_Global, 0,
        k_ESteamNetworkingConfig_Int32,
        &value);

    return ok ? atom_ok : enif_make_tuple2(env, atom_error, enif_make_atom(env, "failed"));
}

// ---------------------------------------------------------------------------
// NIF: set_global_config_float/2 (config_key, float_value)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_set_global_config_float(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    int config_key;
    double value;
    if (!enif_get_int(env, argv[0], &config_key))
        return enif_make_badarg(env);
    if (!enif_get_double(env, argv[1], &value))
        return enif_make_badarg(env);

    float f = (float)value;
    bool ok = SteamAPI_ISteamNetworkingUtils_SetConfigValue(
        get_utils(),
        (ESteamNetworkingConfigValue)config_key,
        k_ESteamNetworkingConfig_Global, 0,
        k_ESteamNetworkingConfig_Float,
        &f);

    return ok ? atom_ok : enif_make_tuple2(env, atom_error, enif_make_atom(env, "failed"));
}

// ---------------------------------------------------------------------------
// NIF: set_global_config_string/2 (config_key, string_value)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_set_global_config_string(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    int config_key;
    char value[1024];
    if (!enif_get_int(env, argv[0], &config_key))
        return enif_make_badarg(env);
    if (!enif_get_string(env, argv[1], value, sizeof(value), ERL_NIF_LATIN1))
        return enif_make_badarg(env);

    bool ok = SteamAPI_ISteamNetworkingUtils_SetConfigValue(
        get_utils(),
        (ESteamNetworkingConfigValue)config_key,
        k_ESteamNetworkingConfig_Global, 0,
        k_ESteamNetworkingConfig_String,
        value);

    return ok ? atom_ok : enif_make_tuple2(env, atom_error, enif_make_atom(env, "failed"));
}

// ---------------------------------------------------------------------------
// NIF: create_socket_pair/1 (use_network_loopback)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_create_socket_pair(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    char loopback_str[6];
    if (!enif_get_atom(env, argv[0], loopback_str, sizeof(loopback_str), ERL_NIF_LATIN1))
        return enif_make_badarg(env);

    bool use_loopback = (strcmp(loopback_str, "true") == 0);

    HSteamNetConnection conn1, conn2;
    bool ok = SteamAPI_ISteamNetworkingSockets_CreateSocketPair(
        get_interface(), &conn1, &conn2, use_loopback, NULL, NULL);

    if (!ok)
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "failed"));

    return enif_make_tuple3(env, atom_ok, enif_make_uint(env, conn1), enif_make_uint(env, conn2));
}

// ---------------------------------------------------------------------------
// NIF: get_identity/0
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_get_identity(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    SteamNetworkingIdentity identity;
    if (!SteamAPI_ISteamNetworkingSockets_GetIdentity(get_interface(), &identity))
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "not_available"));

    char buf[SteamNetworkingIdentity::k_cchMaxString];
    SteamAPI_SteamNetworkingIdentity_ToString(&identity, buf, sizeof(buf));

    return enif_make_tuple2(env, atom_ok, enif_make_string(env, buf, ERL_NIF_LATIN1));
}

// ---------------------------------------------------------------------------
// NIF: init_authentication/0
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_init_authentication(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ESteamNetworkingAvailability result = SteamAPI_ISteamNetworkingSockets_InitAuthentication(get_interface());
    return enif_make_int(env, (int)result);
}

// ---------------------------------------------------------------------------
// NIF: get_authentication_status/0
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_get_authentication_status(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    SteamNetAuthenticationStatus_t details;
    ESteamNetworkingAvailability avail = SteamAPI_ISteamNetworkingSockets_GetAuthenticationStatus(
        get_interface(), &details);

    ERL_NIF_TERM keys[] = { atom_availability, atom_debug_msg };
    ERL_NIF_TERM vals[] = {
        enif_make_int(env, (int)avail),
        enif_make_string(env, details.m_debugMsg, ERL_NIF_LATIN1)
    };
    ERL_NIF_TERM map;
    enif_make_map_from_arrays(env, keys, vals, 2, &map);
    return map;
}

// ---------------------------------------------------------------------------
// NIF: get_certificate_request/0
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_get_certificate_request(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    SteamNetworkingErrMsg errMsg;
    memset(errMsg, 0, sizeof(errMsg));

    // First call to get required size
    int size = 0;
    SteamAPI_ISteamNetworkingSockets_GetCertificateRequest(get_interface(), &size, NULL, errMsg);

    if (size <= 0)
        return enif_make_tuple2(env, atom_error,
            enif_make_string(env, (const char *)errMsg, ERL_NIF_LATIN1));

    // Allocate and get the certificate request
    unsigned char *blob = (unsigned char *)enif_alloc(size);
    if (!blob)
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "allocation_failed"));

    memset(errMsg, 0, sizeof(errMsg));
    bool ok = SteamAPI_ISteamNetworkingSockets_GetCertificateRequest(
        get_interface(), &size, blob, errMsg);

    if (!ok) {
        enif_free(blob);
        return enif_make_tuple2(env, atom_error,
            enif_make_string(env, (const char *)errMsg, ERL_NIF_LATIN1));
    }

    ERL_NIF_TERM bin_term;
    unsigned char *bin_data = enif_make_new_binary(env, size, &bin_term);
    memcpy(bin_data, blob, size);
    enif_free(blob);

    return enif_make_tuple2(env, atom_ok, bin_term);
}

// ---------------------------------------------------------------------------
// NIF: set_certificate/1 (binary_blob)
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_set_certificate(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary bin;
    if (!enif_inspect_binary(env, argv[0], &bin))
        return enif_make_badarg(env);

    SteamNetworkingErrMsg errMsg;
    memset(errMsg, 0, sizeof(errMsg));

    bool ok = SteamAPI_ISteamNetworkingSockets_SetCertificate(
        get_interface(), bin.data, (int)bin.size, errMsg);

    if (!ok)
        return enif_make_tuple2(env, atom_error,
            enif_make_string(env, (const char *)errMsg, ERL_NIF_LATIN1));

    return atom_ok;
}

// ---------------------------------------------------------------------------
// Relay Network, Ping Location, Data Center (POP) functions
// These require the Steam Relay network (not available in open-source GNS).
// Define HAS_STEAM_RELAY_NETWORK when building against a GNS build that
// includes relay support (e.g. the Steamworks SDK redistrib).
// ---------------------------------------------------------------------------

#ifdef HAS_STEAM_RELAY_NETWORK

static ERL_NIF_TERM nif_init_relay_network_access(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    SteamAPI_ISteamNetworkingUtils_InitRelayNetworkAccess(get_utils());
    return atom_ok;
}

static ERL_NIF_TERM nif_get_relay_network_status(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    SteamRelayNetworkStatus_t details;
    ESteamNetworkingAvailability avail = SteamAPI_ISteamNetworkingUtils_GetRelayNetworkStatus(
        get_utils(), &details);

    ERL_NIF_TERM keys[] = {
        atom_availability, atom_debug_msg, atom_ping_in_progress,
        atom_network_config, atom_any_relay
    };
    ERL_NIF_TERM vals[] = {
        enif_make_int(env, (int)avail),
        enif_make_string(env, details.m_debugMsg, ERL_NIF_LATIN1),
        details.m_bPingMeasurementInProgress ? atom_true : atom_false,
        enif_make_int(env, (int)details.m_eAvailNetworkConfig),
        enif_make_int(env, (int)details.m_eAvailAnyRelay)
    };
    ERL_NIF_TERM map;
    enif_make_map_from_arrays(env, keys, vals, 5, &map);
    return map;
}

static ERL_NIF_TERM nif_get_local_ping_location(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    SteamNetworkPingLocation_t location;
    float age = SteamAPI_ISteamNetworkingUtils_GetLocalPingLocation(get_utils(), location);

    if (age < 0)
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "not_available"));

    char loc_str[k_cchMaxSteamNetworkingPingLocationString];
    SteamAPI_ISteamNetworkingUtils_ConvertPingLocationToString(get_utils(), location, loc_str, sizeof(loc_str));

    return enif_make_tuple3(env, atom_ok,
        enif_make_string(env, loc_str, ERL_NIF_LATIN1),
        enif_make_double(env, (double)age));
}

static ERL_NIF_TERM nif_estimate_ping_between_locations(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    char loc1_str[k_cchMaxSteamNetworkingPingLocationString];
    char loc2_str[k_cchMaxSteamNetworkingPingLocationString];

    if (!enif_get_string(env, argv[0], loc1_str, sizeof(loc1_str), ERL_NIF_LATIN1))
        return enif_make_badarg(env);
    if (!enif_get_string(env, argv[1], loc2_str, sizeof(loc2_str), ERL_NIF_LATIN1))
        return enif_make_badarg(env);

    SteamNetworkPingLocation_t loc1, loc2;
    if (!SteamAPI_ISteamNetworkingUtils_ParsePingLocationString(get_utils(), loc1_str, loc1))
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "invalid_location1"));
    if (!SteamAPI_ISteamNetworkingUtils_ParsePingLocationString(get_utils(), loc2_str, loc2))
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "invalid_location2"));

    int ping = SteamAPI_ISteamNetworkingUtils_EstimatePingTimeBetweenTwoLocations(get_utils(), loc1, loc2);
    return enif_make_int(env, ping);
}

static ERL_NIF_TERM nif_estimate_ping_from_local_host(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    char loc_str[k_cchMaxSteamNetworkingPingLocationString];
    if (!enif_get_string(env, argv[0], loc_str, sizeof(loc_str), ERL_NIF_LATIN1))
        return enif_make_badarg(env);

    SteamNetworkPingLocation_t loc;
    if (!SteamAPI_ISteamNetworkingUtils_ParsePingLocationString(get_utils(), loc_str, loc))
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "invalid_location"));

    int ping = SteamAPI_ISteamNetworkingUtils_EstimatePingTimeFromLocalHost(get_utils(), loc);
    return enif_make_int(env, ping);
}

static ERL_NIF_TERM nif_check_ping_data_up_to_date(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    double max_age;
    if (!enif_get_double(env, argv[0], &max_age))
        return enif_make_badarg(env);

    bool ok = SteamAPI_ISteamNetworkingUtils_CheckPingDataUpToDate(get_utils(), (float)max_age);
    return ok ? atom_true : atom_false;
}

static ERL_NIF_TERM nif_get_ping_to_data_center(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int pop_id;
    if (!enif_get_uint(env, argv[0], &pop_id))
        return enif_make_badarg(env);

    SteamNetworkingPOPID via_relay;
    int ping = SteamAPI_ISteamNetworkingUtils_GetPingToDataCenter(get_utils(), pop_id, &via_relay);

    return enif_make_tuple2(env,
        enif_make_int(env, ping),
        enif_make_uint(env, via_relay));
}

static ERL_NIF_TERM nif_get_direct_ping_to_pop(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int pop_id;
    if (!enif_get_uint(env, argv[0], &pop_id))
        return enif_make_badarg(env);

    int ping = SteamAPI_ISteamNetworkingUtils_GetDirectPingToPOP(get_utils(), pop_id);
    return enif_make_int(env, ping);
}

static ERL_NIF_TERM nif_get_pop_count(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    int count = SteamAPI_ISteamNetworkingUtils_GetPOPCount(get_utils());
    return enif_make_int(env, count);
}

static ERL_NIF_TERM nif_get_pop_list(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int max_count;
    if (!enif_get_uint(env, argv[0], &max_count))
        return enif_make_badarg(env);
    if (max_count > 256) max_count = 256;

    SteamNetworkingPOPID list[256];
    int count = SteamAPI_ISteamNetworkingUtils_GetPOPList(get_utils(), list, (int)max_count);

    ERL_NIF_TERM result = enif_make_list(env, 0);
    for (int i = count - 1; i >= 0; i--) {
        result = enif_make_list_cell(env, enif_make_uint(env, list[i]), result);
    }
    return result;
}

#else // !HAS_STEAM_RELAY_NETWORK — stubs

static ERL_NIF_TERM nif_init_relay_network_access(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "steam_relay_required"));
}
static ERL_NIF_TERM nif_get_relay_network_status(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "steam_relay_required"));
}
static ERL_NIF_TERM nif_get_local_ping_location(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "steam_relay_required"));
}
static ERL_NIF_TERM nif_estimate_ping_between_locations(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "steam_relay_required"));
}
static ERL_NIF_TERM nif_estimate_ping_from_local_host(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "steam_relay_required"));
}
static ERL_NIF_TERM nif_check_ping_data_up_to_date(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "steam_relay_required"));
}
static ERL_NIF_TERM nif_get_ping_to_data_center(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "steam_relay_required"));
}
static ERL_NIF_TERM nif_get_direct_ping_to_pop(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "steam_relay_required"));
}
static ERL_NIF_TERM nif_get_pop_count(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "steam_relay_required"));
}
static ERL_NIF_TERM nif_get_pop_list(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "steam_relay_required"));
}

#endif // HAS_STEAM_RELAY_NETWORK

// ---------------------------------------------------------------------------
// NIF: get_local_timestamp/0
// ---------------------------------------------------------------------------

static ERL_NIF_TERM nif_get_local_timestamp(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    SteamNetworkingMicroseconds ts = SteamAPI_ISteamNetworkingUtils_GetLocalTimestamp(get_utils());
    return enif_make_int64(env, ts);
}

// ===========================================================================
// Steam-only: P2P, Relay Auth, Hosted Dedicated Server, Game Coordinator
// All require the Steamworks SDK — symbols not present in the open-source build.
// ===========================================================================

#ifdef HAS_STEAM_DATAGRAM_TYPES

static ERL_NIF_TERM nif_create_listen_socket_p2p(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    int virtual_port;
    if (!enif_get_int(env, argv[0], &virtual_port))
        return enif_make_badarg(env);

    HSteamListenSocket sock = SteamAPI_ISteamNetworkingSockets_CreateListenSocketP2P(
        get_interface(), virtual_port, 0, NULL);

    if (sock == k_HSteamListenSocket_Invalid)
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "invalid_socket"));

    return enif_make_tuple2(env, atom_ok, enif_make_uint(env, sock));
}

static ERL_NIF_TERM nif_connect_p2p(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    char identity_str[256];
    int virtual_port;

    if (!enif_get_string(env, argv[0], identity_str, sizeof(identity_str), ERL_NIF_LATIN1))
        return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &virtual_port))
        return enif_make_badarg(env);

    SteamNetworkingIdentity identity;
    if (!SteamAPI_SteamNetworkingIdentity_ParseString(&identity, sizeof(identity), identity_str))
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "invalid_identity"));

    HSteamNetConnection conn = SteamAPI_ISteamNetworkingSockets_ConnectP2P(
        get_interface(), identity, virtual_port, 0, NULL);

    if (conn == k_HSteamNetConnection_Invalid)
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "invalid_connection"));

    return enif_make_tuple2(env, atom_ok, enif_make_uint(env, conn));
}

static ERL_NIF_TERM nif_received_relay_auth_ticket(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary bin;
    if (!enif_inspect_binary(env, argv[0], &bin))
        return enif_make_badarg(env);

    SteamDatagramRelayAuthTicket parsed;
    bool ok = SteamAPI_ISteamNetworkingSockets_ReceivedRelayAuthTicket(
        get_interface(), bin.data, (int)bin.size, &parsed);

    if (!ok)
        return atom_false;

    ERL_NIF_TERM out;
    unsigned char *buf = enif_make_new_binary(env, sizeof(parsed), &out);
    memcpy(buf, &parsed, sizeof(parsed));

    return enif_make_tuple2(env, atom_ok, out);
}

static ERL_NIF_TERM nif_find_relay_auth_ticket_for_server(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    char identity_str[256];
    int virtual_port;

    if (!enif_get_string(env, argv[0], identity_str, sizeof(identity_str), ERL_NIF_LATIN1))
        return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &virtual_port))
        return enif_make_badarg(env);

    SteamNetworkingIdentity identity;
    if (!SteamAPI_SteamNetworkingIdentity_ParseString(&identity, sizeof(identity), identity_str))
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "invalid_identity"));

    SteamDatagramRelayAuthTicket parsed;
    int seconds = SteamAPI_ISteamNetworkingSockets_FindRelayAuthTicketForServer(
        get_interface(), identity, virtual_port, &parsed);

    if (seconds == 0)
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "not_found"));

    ERL_NIF_TERM out;
    unsigned char *buf = enif_make_new_binary(env, sizeof(parsed), &out);
    memcpy(buf, &parsed, sizeof(parsed));

    return enif_make_tuple3(env, atom_ok, enif_make_int(env, seconds), out);
}

static ERL_NIF_TERM nif_connect_to_hosted_dedicated_server(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    char identity_str[256];
    int virtual_port;

    if (!enif_get_string(env, argv[0], identity_str, sizeof(identity_str), ERL_NIF_LATIN1))
        return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &virtual_port))
        return enif_make_badarg(env);

    SteamNetworkingIdentity identity;
    if (!SteamAPI_SteamNetworkingIdentity_ParseString(&identity, sizeof(identity), identity_str))
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "invalid_identity"));

    HSteamNetConnection conn = SteamAPI_ISteamNetworkingSockets_ConnectToHostedDedicatedServer(
        get_interface(), identity, virtual_port, 0, NULL);

    if (conn == k_HSteamNetConnection_Invalid)
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "invalid_connection"));

    return enif_make_tuple2(env, atom_ok, enif_make_uint(env, conn));
}

static ERL_NIF_TERM nif_get_hosted_dedicated_server_port(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    uint16 port = SteamAPI_ISteamNetworkingSockets_GetHostedDedicatedServerPort(get_interface());
    return enif_make_uint(env, port);
}

static ERL_NIF_TERM nif_get_hosted_dedicated_server_pop_id(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    SteamNetworkingPOPID pop_id = SteamAPI_ISteamNetworkingSockets_GetHostedDedicatedServerPOPID(get_interface());
    return enif_make_uint(env, pop_id);
}

static ERL_NIF_TERM nif_get_hosted_dedicated_server_address(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    SteamDatagramHostedAddress addr;
    EResult result = SteamAPI_ISteamNetworkingSockets_GetHostedDedicatedServerAddress(
        get_interface(), &addr);

    if (result != k_EResultOK)
        return enif_make_tuple2(env, atom_error, enif_make_int(env, (int)result));

    ERL_NIF_TERM out;
    unsigned char *buf = enif_make_new_binary(env, addr.m_cbSize, &out);
    memcpy(buf, addr.m_data, addr.m_cbSize);

    return enif_make_tuple2(env, atom_ok, out);
}

static ERL_NIF_TERM nif_create_hosted_dedicated_server_listen_socket(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    int virtual_port;
    if (!enif_get_int(env, argv[0], &virtual_port))
        return enif_make_badarg(env);

    HSteamListenSocket sock = SteamAPI_ISteamNetworkingSockets_CreateHostedDedicatedServerListenSocket(
        get_interface(), virtual_port, 0, NULL);

    if (sock == k_HSteamListenSocket_Invalid)
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "invalid_socket"));

    return enif_make_tuple2(env, atom_ok, enif_make_uint(env, sock));
}

static ERL_NIF_TERM nif_get_game_coordinator_server_login(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    SteamDatagramGameCoordinatorServerLogin login_info;

    // First call to get required blob size
    int blob_size = 0;
    SteamAPI_ISteamNetworkingSockets_GetGameCoordinatorServerLogin(
        get_interface(), &login_info, &blob_size, NULL);

    if (blob_size <= 0)
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "unavailable"));

    unsigned char *blob = (unsigned char *)enif_alloc(blob_size);
    if (!blob)
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "allocation_failed"));

    EResult result = SteamAPI_ISteamNetworkingSockets_GetGameCoordinatorServerLogin(
        get_interface(), &login_info, &blob_size, blob);

    if (result != k_EResultOK) {
        enif_free(blob);
        return enif_make_tuple2(env, atom_error, enif_make_int(env, (int)result));
    }

    ERL_NIF_TERM login_term;
    unsigned char *login_buf = enif_make_new_binary(env, sizeof(login_info), &login_term);
    memcpy(login_buf, &login_info, sizeof(login_info));

    ERL_NIF_TERM blob_term;
    unsigned char *blob_buf = enif_make_new_binary(env, blob_size, &blob_term);
    memcpy(blob_buf, blob, blob_size);
    enif_free(blob);

    return enif_make_tuple3(env, atom_ok, login_term, blob_term);
}

#else // !HAS_STEAM_DATAGRAM_TYPES — stubs for all Steam-only functions

static ERL_NIF_TERM nif_create_listen_socket_p2p(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "steamworks_sdk_required"));
}
static ERL_NIF_TERM nif_connect_p2p(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "steamworks_sdk_required"));
}
static ERL_NIF_TERM nif_received_relay_auth_ticket(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "steamworks_sdk_required"));
}
static ERL_NIF_TERM nif_find_relay_auth_ticket_for_server(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "steamworks_sdk_required"));
}
static ERL_NIF_TERM nif_connect_to_hosted_dedicated_server(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "steamworks_sdk_required"));
}
static ERL_NIF_TERM nif_get_hosted_dedicated_server_port(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "steamworks_sdk_required"));
}
static ERL_NIF_TERM nif_get_hosted_dedicated_server_pop_id(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "steamworks_sdk_required"));
}
static ERL_NIF_TERM nif_get_hosted_dedicated_server_address(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "steamworks_sdk_required"));
}
static ERL_NIF_TERM nif_create_hosted_dedicated_server_listen_socket(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "steamworks_sdk_required"));
}
static ERL_NIF_TERM nif_get_game_coordinator_server_login(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "steamworks_sdk_required"));
}

#endif // HAS_STEAM_DATAGRAM_TYPES

// ---------------------------------------------------------------------------
// NIF table
// ---------------------------------------------------------------------------

static ErlNifFunc nif_funcs[] = {
    {"gns_init",                          0, nif_gns_init,                          0},
    {"gns_kill",                          0, nif_gns_kill,                          0},
    {"poll_callbacks",                    0, nif_poll_callbacks,                    0},
    {"poll_connection_status_changes",    1, nif_poll_connection_status_changes,    0},
    {"create_listen_socket_ip",           2, nif_create_listen_socket_ip,           0},
    {"connect_by_ip_address",             2, nif_connect_by_ip_address,             0},
    {"accept_connection",                 1, nif_accept_connection,                 0},
    {"close_connection",                  4, nif_close_connection,                  0},
    {"close_listen_socket",               1, nif_close_listen_socket,               0},
    {"create_poll_group",                 0, nif_create_poll_group,                 0},
    {"destroy_poll_group",                1, nif_destroy_poll_group,                0},
    {"set_connection_poll_group",         2, nif_set_connection_poll_group,         0},
    {"send_message_to_connection",        3, nif_send_message_to_connection,        0},
    {"flush_messages_on_connection",      1, nif_flush_messages_on_connection,      0},
    {"receive_messages_on_connection",    2, nif_receive_messages_on_connection,    0},
    {"receive_messages_on_poll_group",    2, nif_receive_messages_on_poll_group,    0},
    {"get_connection_info",               1, nif_get_connection_info,               0},
    {"get_connection_real_time_status",   2, nif_get_connection_real_time_status,   0},
    {"set_connection_user_data",          2, nif_set_connection_user_data,          0},
    {"configure_connection_lanes",        3, nif_configure_connection_lanes,        0},
    {"get_connection_user_data",           1, nif_get_connection_user_data,           0},
    {"get_detailed_connection_status",     1, nif_get_detailed_connection_status,     0},
    {"get_listen_socket_address",          1, nif_get_listen_socket_address,          0},
    {"set_connection_name",                2, nif_set_connection_name,                0},
    {"get_connection_name",                1, nif_get_connection_name,                0},
    {"send_messages",                      1, nif_send_messages,                      0},
    {"set_debug_output_level",             1, nif_set_debug_output_level,             0},
    {"poll_debug_messages",                1, nif_poll_debug_messages,                0},
    {"set_global_config_int",              2, nif_set_global_config_int,              0},
    {"set_global_config_float",            2, nif_set_global_config_float,            0},
    {"set_global_config_string",           2, nif_set_global_config_string,           0},
    {"create_socket_pair",                  1, nif_create_socket_pair,                 0},
    {"get_identity",                        0, nif_get_identity,                       0},
    {"init_authentication",                 0, nif_init_authentication,                0},
    {"get_authentication_status",           0, nif_get_authentication_status,          0},
    {"get_certificate_request",             0, nif_get_certificate_request,            0},
    {"set_certificate",                     1, nif_set_certificate,                    0},
    {"init_relay_network_access",           0, nif_init_relay_network_access,          0},
    {"get_relay_network_status",            0, nif_get_relay_network_status,           0},
    {"get_local_ping_location",             0, nif_get_local_ping_location,            0},
    {"estimate_ping_between_locations",     2, nif_estimate_ping_between_locations,    0},
    {"estimate_ping_from_local_host",       1, nif_estimate_ping_from_local_host,      0},
    {"check_ping_data_up_to_date",          1, nif_check_ping_data_up_to_date,         0},
    {"get_ping_to_data_center",             1, nif_get_ping_to_data_center,            0},
    {"get_direct_ping_to_pop",              1, nif_get_direct_ping_to_pop,             0},
    {"get_pop_count",                       0, nif_get_pop_count,                      0},
    {"get_pop_list",                        1, nif_get_pop_list,                       0},
    {"get_local_timestamp",                 0, nif_get_local_timestamp,                0},
    // Steam-only
    {"create_listen_socket_p2p",             1, nif_create_listen_socket_p2p,           0},
    {"connect_p2p",                          2, nif_connect_p2p,                        0},
    {"received_relay_auth_ticket",           1, nif_received_relay_auth_ticket,         0},
    {"find_relay_auth_ticket_for_server",    2, nif_find_relay_auth_ticket_for_server,  0},
    {"connect_to_hosted_dedicated_server",   2, nif_connect_to_hosted_dedicated_server, 0},
    {"get_hosted_dedicated_server_port",     0, nif_get_hosted_dedicated_server_port,   0},
    {"get_hosted_dedicated_server_pop_id",   0, nif_get_hosted_dedicated_server_pop_id, 0},
    {"get_hosted_dedicated_server_address",  0, nif_get_hosted_dedicated_server_address,0},
    {"create_hosted_dedicated_server_listen_socket", 1, nif_create_hosted_dedicated_server_listen_socket, 0},
    {"get_game_coordinator_server_login",    0, nif_get_game_coordinator_server_login,  0},
};

// ---------------------------------------------------------------------------
// NIF load callback
// ---------------------------------------------------------------------------

static int load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM load_info) {
    atom_ok     = enif_make_atom(env, "ok");
    atom_error  = enif_make_atom(env, "error");
    atom_true   = enif_make_atom(env, "true");
    atom_false  = enif_make_atom(env, "false");

    atom_conn      = enif_make_atom(env, "conn");
    atom_old_state = enif_make_atom(env, "old_state");
    atom_new_state = enif_make_atom(env, "new_state");
    atom_end_reason = enif_make_atom(env, "end_reason");
    atom_end_debug = enif_make_atom(env, "end_debug");

    atom_state      = enif_make_atom(env, "state");
    atom_listen_socket = enif_make_atom(env, "listen_socket");
    atom_remote_address = enif_make_atom(env, "remote_address");
    atom_remote_port = enif_make_atom(env, "remote_port");
    atom_user_data  = enif_make_atom(env, "user_data");
    atom_flags      = enif_make_atom(env, "flags");
    atom_connection_description = enif_make_atom(env, "connection_description");

    atom_ping = enif_make_atom(env, "ping");
    atom_quality_local = enif_make_atom(env, "quality_local");
    atom_quality_remote = enif_make_atom(env, "quality_remote");
    atom_out_packets_per_sec = enif_make_atom(env, "out_packets_per_sec");
    atom_out_bytes_per_sec = enif_make_atom(env, "out_bytes_per_sec");
    atom_in_packets_per_sec = enif_make_atom(env, "in_packets_per_sec");
    atom_in_bytes_per_sec = enif_make_atom(env, "in_bytes_per_sec");
    atom_send_rate_bytes_per_sec = enif_make_atom(env, "send_rate_bytes_per_sec");
    atom_pending_unreliable = enif_make_atom(env, "pending_unreliable");
    atom_pending_reliable = enif_make_atom(env, "pending_reliable");
    atom_sent_unacked_reliable = enif_make_atom(env, "sent_unacked_reliable");
    atom_queue_time_usec = enif_make_atom(env, "queue_time_usec");

    atom_payload = enif_make_atom(env, "payload");
    atom_message_number = enif_make_atom(env, "message_number");
    atom_channel = enif_make_atom(env, "channel");
    atom_lane = enif_make_atom(env, "lane");
    atom_conn_user_data = enif_make_atom(env, "conn_user_data");

    atom_send_unreliable = enif_make_atom(env, "unreliable");
    atom_send_reliable = enif_make_atom(env, "reliable");
    atom_send_no_nagle = enif_make_atom(env, "no_nagle");
    atom_send_no_delay = enif_make_atom(env, "no_delay");

    atom_type    = enif_make_atom(env, "type");
    atom_msg     = enif_make_atom(env, "msg");
    atom_address = enif_make_atom(env, "address");
    atom_port    = enif_make_atom(env, "port");

    atom_availability     = enif_make_atom(env, "availability");
    atom_debug_msg        = enif_make_atom(env, "debug_msg");
    atom_ping_in_progress = enif_make_atom(env, "ping_in_progress");
    atom_network_config   = enif_make_atom(env, "network_config");
    atom_any_relay        = enif_make_atom(env, "any_relay");

    return 0;
}

ERL_NIF_INIT(Elixir.GameNetworkingSockets.Nif, nif_funcs, load, NULL, NULL, NULL)
