#include "rcpp_dcmtk.h"
#include <thread>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>
#endif

namespace dicomtk {

static void push_u16_be(std::vector<uint8_t>& b, uint16_t v) {
  b.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
  b.push_back(static_cast<uint8_t>(v & 0xFF));
}

static void push_u32_be(std::vector<uint8_t>& b, uint32_t v) {
  b.push_back(static_cast<uint8_t>((v >> 24) & 0xFF));
  b.push_back(static_cast<uint8_t>((v >> 16) & 0xFF));
  b.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
  b.push_back(static_cast<uint8_t>(v & 0xFF));
}

static void push_u16_le(std::vector<uint8_t>& b, uint16_t v) {
  b.push_back(static_cast<uint8_t>(v & 0xFF));
  b.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
}

static void push_u32_le(std::vector<uint8_t>& b, uint32_t v) {
  b.push_back(static_cast<uint8_t>(v & 0xFF));
  b.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
  b.push_back(static_cast<uint8_t>((v >> 16) & 0xFF));
  b.push_back(static_cast<uint8_t>((v >> 24) & 0xFF));
}

static std::vector<uint8_t> build_associate_rq_pdu(const std::string& called_ae,
                                                   const std::string& calling_ae,
                                                   const std::string& abstract_syntax) {
  std::vector<uint8_t> payload;
  push_u16_be(payload, 0x0001); // Protocol version 1
  push_u16_be(payload, 0x0000); // Reserved

  std::string called = called_ae.substr(0, 16);
  called.append(16 - called.size(), ' ');
  payload.insert(payload.end(), called.begin(), called.end());

  std::string calling = calling_ae.substr(0, 16);
  calling.append(16 - calling.size(), ' ');
  payload.insert(payload.end(), calling.begin(), calling.end());

  payload.resize(payload.size() + 32, 0); // 32 reserved bytes

  // Application Context Item (0x10): "1.2.840.10008.3.1.1.1"
  std::string app_ctx = "1.2.840.10008.3.1.1.1";
  payload.push_back(0x10);
  payload.push_back(0x00);
  push_u16_be(payload, static_cast<uint16_t>(app_ctx.size()));
  payload.insert(payload.end(), app_ctx.begin(), app_ctx.end());

  // Presentation Context Item (0x20)
  std::vector<uint8_t> pres_ctx;
  pres_ctx.push_back(0x01); // Context ID = 1
  pres_ctx.push_back(0x00);
  pres_ctx.push_back(0x00);
  pres_ctx.push_back(0x00);

  // Abstract Syntax Sub-item (0x30)
  pres_ctx.push_back(0x30);
  pres_ctx.push_back(0x00);
  push_u16_be(pres_ctx, static_cast<uint16_t>(abstract_syntax.size()));
  pres_ctx.insert(pres_ctx.end(), abstract_syntax.begin(), abstract_syntax.end());

  // Transfer Syntax Sub-item (0x40): Implicit VR Little Endian "1.2.840.10008.1.2"
  std::string ts_uid = "1.2.840.10008.1.2";
  pres_ctx.push_back(0x40);
  pres_ctx.push_back(0x00);
  push_u16_be(pres_ctx, static_cast<uint16_t>(ts_uid.size()));
  pres_ctx.insert(pres_ctx.end(), ts_uid.begin(), ts_uid.end());

  payload.push_back(0x20);
  payload.push_back(0x00);
  push_u16_be(payload, static_cast<uint16_t>(pres_ctx.size()));
  payload.insert(payload.end(), pres_ctx.begin(), pres_ctx.end());

  // User Information Item (0x50) with Max PDU Length (0x51) = 16384
  std::vector<uint8_t> user_info;
  user_info.push_back(0x51);
  user_info.push_back(0x00);
  push_u16_be(user_info, 4);
  push_u32_be(user_info, 16384);

  payload.push_back(0x50);
  payload.push_back(0x00);
  push_u16_be(payload, static_cast<uint16_t>(user_info.size()));
  payload.insert(payload.end(), user_info.begin(), user_info.end());

  std::vector<uint8_t> pdu;
  pdu.push_back(0x01); // A-ASSOCIATE-RQ
  pdu.push_back(0x00);
  push_u32_be(pdu, static_cast<uint32_t>(payload.size()));
  pdu.insert(pdu.end(), payload.begin(), payload.end());
  return pdu;
}

static std::vector<uint8_t> build_cecho_rq_pdu() {
  std::string uid = "1.2.840.10008.1.1"; // Verification SOP Class
  if (uid.size() % 2 == 1) uid.push_back('\0');

  std::vector<uint8_t> cmd_elems;
  // (0000,0002) AffectedSOPClassUID
  push_u16_le(cmd_elems, 0x0000);
  push_u16_le(cmd_elems, 0x0002);
  push_u32_le(cmd_elems, static_cast<uint32_t>(uid.size()));
  cmd_elems.insert(cmd_elems.end(), uid.begin(), uid.end());

  // (0000,0100) CommandField = 0x0030 (C-ECHO-RQ)
  push_u16_le(cmd_elems, 0x0000);
  push_u16_le(cmd_elems, 0x0100);
  push_u32_le(cmd_elems, 2);
  push_u16_le(cmd_elems, 0x0030);

  // (0000,0110) MessageID = 1
  push_u16_le(cmd_elems, 0x0000);
  push_u16_le(cmd_elems, 0x0110);
  push_u32_le(cmd_elems, 2);
  push_u16_le(cmd_elems, 1);

  // (0000,0800) CommandDataSetType = 0x0101 (no dataset)
  push_u16_le(cmd_elems, 0x0000);
  push_u16_le(cmd_elems, 0x0800);
  push_u32_le(cmd_elems, 2);
  push_u16_le(cmd_elems, 0x0101);

  std::vector<uint8_t> cmd;
  // (0000,0000) CommandGroupLength
  push_u16_le(cmd, 0x0000);
  push_u16_le(cmd, 0x0000);
  push_u32_le(cmd, 4);
  push_u32_le(cmd, static_cast<uint32_t>(cmd_elems.size()));
  cmd.insert(cmd.end(), cmd_elems.begin(), cmd_elems.end());

  // PDV item: length (4 bytes BE) + context ID (1) + message control header (0x03 = command, last fragment)
  std::vector<uint8_t> pdv;
  push_u32_be(pdv, static_cast<uint32_t>(cmd.size() + 2));
  pdv.push_back(0x01);
  pdv.push_back(0x03);
  pdv.insert(pdv.end(), cmd.begin(), cmd.end());

  // P-DATA-TF PDU (0x04)
  std::vector<uint8_t> pdu;
  pdu.push_back(0x04);
  pdu.push_back(0x00);
  push_u32_be(pdu, static_cast<uint32_t>(pdv.size()));
  pdu.insert(pdu.end(), pdv.begin(), pdv.end());
  return pdu;
}

static std::vector<uint8_t> build_release_rq_pdu() {
  std::vector<uint8_t> pdu = {0x05, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00};
  return pdu;
}

} // namespace dicomtk

// [[Rcpp::export]]
Rcpp::List cpp_dicom_echo(const std::string& host,
                          int port,
                          const std::string& called_ae = "ANY-SCP",
                          const std::string& calling_ae = "DICOMTK",
                          int timeout_ms = 5000) {
#ifdef _WIN32
  WSADATA wsa;
  WSAStartup(MAKEWORD(2, 2), &wsa);
#endif

  auto start_time = std::chrono::steady_clock::now();
  struct addrinfo hints, *res = nullptr;
  std::memset(&hints, 0, sizeof(hints));
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;

  std::string port_str = std::to_string(port);
  int gai = getaddrinfo(host.c_str(), port_str.c_str(), &hints, &res);
  if (gai != 0 || res == nullptr) {
#ifdef _WIN32
    WSACleanup();
#endif
    return Rcpp::List::create(
      Rcpp::_["success"] = false,
      Rcpp::_["status"] = "DNS_RESOLUTION_FAILED",
      Rcpp::_["message"] = "Could not resolve host: " + host,
      Rcpp::_["elapsed_ms"] = NA_REAL
    );
  }

#ifdef _WIN32
  SOCKET sock = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
  if (sock == INVALID_SOCKET) {
    freeaddrinfo(res);
    WSACleanup();
    return Rcpp::List::create(
      Rcpp::_["success"] = false,
      Rcpp::_["status"] = "SOCKET_ERROR",
      Rcpp::_["message"] = "Failed to create TCP socket",
      Rcpp::_["elapsed_ms"] = NA_REAL
    );
  }
  DWORD tv = static_cast<DWORD>(timeout_ms);
  setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&tv), sizeof(tv));
  setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, reinterpret_cast<const char*>(&tv), sizeof(tv));
#else
  int sock = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
  if (sock < 0) {
    freeaddrinfo(res);
    return Rcpp::List::create(
      Rcpp::_["success"] = false,
      Rcpp::_["status"] = "SOCKET_ERROR",
      Rcpp::_["message"] = "Failed to create TCP socket",
      Rcpp::_["elapsed_ms"] = NA_REAL
    );
  }
#ifdef SO_NOSIGPIPE
  int nosig = 1;
  setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &nosig, sizeof(nosig));
#endif
  struct timeval tv;
  tv.tv_sec = timeout_ms / 1000;
  tv.tv_usec = (timeout_ms % 1000) * 1000;
  setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
  setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
#endif

  int conn = connect(sock, res->ai_addr, static_cast<int>(res->ai_addrlen));
  freeaddrinfo(res);
  if (conn != 0) {
#ifdef _WIN32
    closesocket(sock);
    WSACleanup();
#else
    close(sock);
#endif
    return Rcpp::List::create(
      Rcpp::_["success"] = false,
      Rcpp::_["status"] = "CONNECTION_REFUSED",
      Rcpp::_["message"] = "Could not connect to " + host + ":" + port_str,
      Rcpp::_["elapsed_ms"] = NA_REAL
    );
  }

  // Send A-ASSOCIATE-RQ for Verification SOP Class (1.2.840.10008.1.1)
  std::vector<uint8_t> assoc_rq = dicomtk::build_associate_rq_pdu(called_ae, calling_ae, "1.2.840.10008.1.1");
  send(sock, reinterpret_cast<const char*>(assoc_rq.data()), static_cast<int>(assoc_rq.size()), 0);

  uint8_t pdu_hdr[6];
  int nread = recv(sock, reinterpret_cast<char*>(pdu_hdr), 6, 0);
  if (nread != 6 || pdu_hdr[0] != 0x02) { // 0x02 = A-ASSOCIATE-AC
#ifdef _WIN32
    closesocket(sock);
    WSACleanup();
#else
    close(sock);
#endif
    return Rcpp::List::create(
      Rcpp::_["success"] = false,
      Rcpp::_["status"] = "ASSOCIATION_REJECTED",
      Rcpp::_["message"] = "PACS peer did not accept association (PDU type: " +
                           std::to_string(nread > 0 ? pdu_hdr[0] : -1) + ")",
      Rcpp::_["elapsed_ms"] = NA_REAL
    );
  }

  uint32_t assoc_len = (static_cast<uint32_t>(pdu_hdr[2]) << 24) |
                       (static_cast<uint32_t>(pdu_hdr[3]) << 16) |
                       (static_cast<uint32_t>(pdu_hdr[4]) << 8) |
                       static_cast<uint32_t>(pdu_hdr[5]);
  std::vector<uint8_t> assoc_body(assoc_len);
  uint32_t got = 0;
  while (got < assoc_len) {
    int r = recv(sock, reinterpret_cast<char*>(&assoc_body[got]), static_cast<int>(assoc_len - got), 0);
    if (r <= 0) break;
    got += static_cast<uint32_t>(r);
  }

  // Send C-ECHO-RQ
  std::vector<uint8_t> echo_rq = dicomtk::build_cecho_rq_pdu();
  send(sock, reinterpret_cast<const char*>(echo_rq.data()), static_cast<int>(echo_rq.size()), 0);

  int echo_read = recv(sock, reinterpret_cast<char*>(pdu_hdr), 6, 0);
  bool ok = (echo_read == 6 && pdu_hdr[0] == 0x04);
  if (ok) {
    uint32_t echo_len = (static_cast<uint32_t>(pdu_hdr[2]) << 24) |
                        (static_cast<uint32_t>(pdu_hdr[3]) << 16) |
                        (static_cast<uint32_t>(pdu_hdr[4]) << 8) |
                        static_cast<uint32_t>(pdu_hdr[5]);
    std::vector<uint8_t> echo_body(echo_len);
    uint32_t egot = 0;
    while (egot < echo_len) {
      int r = recv(sock, reinterpret_cast<char*>(&echo_body[egot]), static_cast<int>(echo_len - egot), 0);
      if (r <= 0) break;
      egot += static_cast<uint32_t>(r);
    }
  }

  // Send A-RELEASE-RQ and drain A-RELEASE-RP
  std::vector<uint8_t> rel_rq = dicomtk::build_release_rq_pdu();
  send(sock, reinterpret_cast<const char*>(rel_rq.data()), static_cast<int>(rel_rq.size()), 0);
  uint8_t rel_rp_buf[10];
  recv(sock, reinterpret_cast<char*>(rel_rp_buf), 10, 0);

#ifdef _WIN32
  closesocket(sock);
  WSACleanup();
#else
  close(sock);
#endif

  auto end_time = std::chrono::steady_clock::now();
  double elapsed_ms = std::chrono::duration<double, std::milli>(end_time - start_time).count();

  return Rcpp::List::create(
    Rcpp::_["success"] = ok,
    Rcpp::_["status"] = ok ? "SUCCESS" : "ECHO_FAILED",
    Rcpp::_["message"] = ok ? "C-ECHO succeeded" : "Failed receiving C-ECHO-RSP",
    Rcpp::_["elapsed_ms"] = elapsed_ms
  );
}

// [[Rcpp::export]]
Rcpp::List cpp_dicom_echo_loopback_test(const std::string& called_ae = "ORTHANC",
                                        const std::string& calling_ae = "DICOMTK") {
#ifdef _WIN32
  WSADATA wsa;
  WSAStartup(MAKEWORD(2, 2), &wsa);
  SOCKET srv = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
#else
  int srv = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
#endif
  sockaddr_in addr;
  std::memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  addr.sin_port = 0; // Ephemeral port

  if (bind(srv, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0 ||
      listen(srv, 1) != 0) {
#ifdef _WIN32
    closesocket(srv);
    WSACleanup();
#else
    close(srv);
#endif
    return Rcpp::List::create(Rcpp::_["success"] = false, Rcpp::_["status"] = "BIND_FAILED");
  }

#ifdef _WIN32
  int addrlen = sizeof(addr);
#else
  socklen_t addrlen = sizeof(addr);
#endif
  getsockname(srv, reinterpret_cast<sockaddr*>(&addr), &addrlen);
  int bound_port = ntohs(addr.sin_port);

  std::thread scp_thread([srv]() {
    sockaddr_in cli_addr;
#ifdef _WIN32
    int cli_len = sizeof(cli_addr);
    SOCKET conn = accept(srv, reinterpret_cast<sockaddr*>(&cli_addr), &cli_len);
    if (conn == INVALID_SOCKET) {
      closesocket(srv);
      return;
    }
#else
    socklen_t cli_len = sizeof(cli_addr);
    int conn = accept(srv, reinterpret_cast<sockaddr*>(&cli_addr), &cli_len);
    if (conn < 0) {
      close(srv);
      return;
    }
#ifdef SO_NOSIGPIPE
    int nosig = 1;
    setsockopt(conn, SOL_SOCKET, SO_NOSIGPIPE, &nosig, sizeof(nosig));
#endif
#endif
    int send_flags = 0;
#ifdef MSG_NOSIGNAL
    send_flags = MSG_NOSIGNAL;
#endif
    uint8_t hdr[6];
    // 1. Receive A-ASSOCIATE-RQ (0x01) and reply A-ASSOCIATE-AC (0x02)
    if (recv(conn, reinterpret_cast<char*>(hdr), 6, 0) == 6 && hdr[0] == 0x01) {
      uint32_t len = (static_cast<uint32_t>(hdr[2]) << 24) |
                     (static_cast<uint32_t>(hdr[3]) << 16) |
                     (static_cast<uint32_t>(hdr[4]) << 8) |
                     static_cast<uint32_t>(hdr[5]);
      std::vector<uint8_t> body(len);
      uint32_t got = 0;
      while (got < len) {
        int r = recv(conn, reinterpret_cast<char*>(&body[got]), static_cast<int>(len - got), 0);
        if (r <= 0) break;
        got += static_cast<uint32_t>(r);
      }
      hdr[0] = 0x02; // A-ASSOCIATE-AC
      send(conn, reinterpret_cast<const char*>(hdr), 6, send_flags);
      send(conn, reinterpret_cast<const char*>(body.data()), static_cast<int>(body.size()), send_flags);

      // 2. Receive P-DATA-TF C-ECHO-RQ (0x04) and reply C-ECHO-RSP (0x04)
      if (recv(conn, reinterpret_cast<char*>(hdr), 6, 0) == 6 && hdr[0] == 0x04) {
        uint32_t plen = (static_cast<uint32_t>(hdr[2]) << 24) |
                        (static_cast<uint32_t>(hdr[3]) << 16) |
                        (static_cast<uint32_t>(hdr[4]) << 8) |
                        static_cast<uint32_t>(hdr[5]);
        std::vector<uint8_t> pbody(plen);
        uint32_t pgot = 0;
        while (pgot < plen) {
          int r = recv(conn, reinterpret_cast<char*>(&pbody[pgot]), static_cast<int>(plen - pgot), 0);
          if (r <= 0) break;
          pgot += static_cast<uint32_t>(r);
        }
        send(conn, reinterpret_cast<const char*>(hdr), 6, send_flags);
        send(conn, reinterpret_cast<const char*>(pbody.data()), static_cast<int>(pbody.size()), send_flags);
      }

      // 3. Receive A-RELEASE-RQ (0x05) and reply A-RELEASE-RP (0x06)
      uint8_t rel_buf[10];
      recv(conn, reinterpret_cast<char*>(rel_buf), 10, 0);
      uint8_t rel_rp[10] = {0x06, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00};
      send(conn, reinterpret_cast<const char*>(rel_rp), 10, send_flags);
    }
#ifdef _WIN32
    closesocket(conn);
    closesocket(srv);
#else
    close(conn);
    close(srv);
#endif
  });

  Rcpp::List res = cpp_dicom_echo("127.0.0.1", bound_port, called_ae, calling_ae, 3000);
  if (scp_thread.joinable()) {
    scp_thread.join();
  }
#ifdef _WIN32
  WSACleanup();
#endif
  res["port"] = bound_port;
  return res;
}

