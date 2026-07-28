#!/bin/sh
# Patch ExMCP 0.12.x to echo back the client's protocol version
# instead of hardcoding 2025-11-25. Fixes Claude Code tool registration.
set -e

MH="deps/ex_mcp/lib/ex_mcp/message_processor/method_handlers.ex"
HP="deps/ex_mcp/lib/ex_mcp/http_plug.ex"

# 1. method_handlers.ex: rename _params -> params in initialize handlers
sed -i.bak 's/def handle_initialize(conn, handler, :direct, _params,/def handle_initialize(conn, handler, :direct, params,/' "$MH"
sed -i.bak 's/def handle_initialize(conn, server_pid, :genserver, _params,/def handle_initialize(conn, server_pid, :genserver, params,/' "$MH"

# 2. Replace hardcoded protocol version with client's version
sed -i.bak 's/"protocolVersion" => @default_protocol_version,/"protocolVersion" => Map.get(params, "protocolVersion", @default_protocol_version),/' "$MH"

# 3. http_plug.ex: add a helper that echoes the client version with IO.inspect debug logging
sed -i.bak 's/defp add_protocol_version_header(conn) do/defp client_protocol_version(conn) do\
    case get_req_header(conn, "mcp-protocol-version") do\
      [v] when is_binary(v) and v != "" ->\
        IO.inspect(v, label: "MCP protocol version from header")\
        v\
      _ ->\
        IO.inspect("2025-03-26", label: "MCP no protocol-version header, fallback")\
        "2025-03-26"\
    end\
  end\
\
  defp add_protocol_version_header(conn) do/' "$HP"
sed -i.bak 's/put_resp_header(conn, "mcp-protocol-version", VersionRegistry.latest_version())/put_resp_header(conn, "mcp-protocol-version", client_protocol_version(conn))/' "$HP"

# 4. Add IO.inspect for all request headers on POST /mcp
sed -i.bak 's/Logger.debug("HttpPlug: POST request to #{conn.request_path}")/IO.inspect(conn.req_headers, label: "MCP POST headers")/' "$HP"

# Clean up backup files
rm -f "$MH.bak" "$HP.bak"

echo "ExMCP protocol version patch applied successfully"
