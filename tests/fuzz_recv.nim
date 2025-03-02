when not defined(mummyNoWorkers):
  {.error: "Requires -d:mummyNoWorkers".}

include mummy

import std/random
randomize()

const iterations = 1000

proc randomWhitespace(): string =
  let len = rand(0 ..< 10)
  for i in 0 ..< len:
    result &= ' '

proc randomAsciiString(): string =
  let len = rand(0 ..< 20)
  for i in 0 ..< len:
    result &= rand(33 .. 126).char

block:
  echo "Fuzzing headerContainsToken"

  proc randomToken(): string =
    let len = rand(0 ..< 10)
    for i in 0 ..< len:
      var c: char
      while true:
        c = rand(33 .. 126).char
        if c != ','.char:
          break
      result &= c.char

  for i in 0 ..< iterations:
    var tokens: seq[seq[string]]
    tokens.setLen(10)

    var headers: HttpHeaders
    for i in 0 ..< 10:
      let numTokens = rand(0 ..< 10)
      if numTokens > 0:
        var v: string
        for j in 0 ..< numTokens:
          let token = randomToken()
          tokens[i].add(token)
          if j > 0:
            v &= randomWhitespace() & ','
          v &= randomWhitespace() & token
        headers[$i] = v
      else:
        let v = randomToken()
        tokens[i].add(v)
        headers[$i] = v

    for i in 0 ..< tokens.len:
      for j in 0 ..< tokens[i].len:
        if tokens[i][j].len > 0 and
          not headers.headerContainsToken($i, toLowerAscii(tokens[i][j])):
          echo "header: ", headers[$i]
          echo "token: ", tokens[i][j]
          doAssert false

block:
  echo "Fuzzing afterRecvHttp"

  proc randomHeader(): string =
    let len = rand(0 ..< 10)
    for i in 0 ..< len:
      var c: char
      while true:
        c = rand(33 .. 126).char
        if c != ':':
          break
      result &= c.char

  proc handler(request: Request) =
    discard

  block:
    echo "Headers"

    for i in 0 ..< iterations:
      let handleData = HandleData()

      # Add request line
      var
        httpMethod = randomAsciiString()
        uri = randomAsciiString()
      handleData.recvBuffer.add(httpMethod)
      handleData.recvBuffer.add(' ')
      handleData.recvBuffer.add(uri)
      handleData.recvBuffer.add(' ')
      case rand(0 .. 2):
      of 0:
        handleData.recvBuffer.add(http10)
      of 1:
        handleData.recvBuffer.add(http11)
      else:
        handleData.recvBuffer.add(randomAsciiString())
      handleData.recvBuffer.add("\r\n")

      # Add headers
      let numHeaders = rand(1 ..< 10)
      var headers: seq[string]
      for i in 0 ..< numHeaders:
        let header = randomHeader()
        headers.add(header)
        handleData.recvBuffer.add(header)
        handleData.recvBuffer.add(":")
        handleData.recvBuffer.add(randomWhitespace())
        handleData.recvBuffer.add(randomAsciiString())
        handleData.recvBuffer.add(randomWhitespace())
        handleData.recvBuffer.add("\r\n")
      handleData.recvBuffer.add("\r\n")

      handleData.bytesReceived = handleData.recvBuffer.len

      let
        server = newServer(handler)
        clientSocket = 1.SocketHandle
        closingConnection = server.afterRecvHttp(
          clientSocket,
          handleData
        )
      if not closingConnection:
        let request = server.taskQueue.popFirst().request
        doAssert request.httpMethod == httpMethod
        doAssert request.uri == uri
        doAssert request.headers.len == numHeaders
        for i in 0 ..< numHeaders:
          doAssert headers[i] in request.headers
      server.close()

  block:
    echo "Transfer-Encoding: chunked"

    for i in 0 ..< iterations:
      let handleData = HandleData()

      handleData.recvBuffer.add("GET / HTTP/1.1\r\n")
      handleData.recvBuffer.add("Transfer-Encoding: chunked\r\n")
      handleData.recvBuffer.add("\r\n")

      var body: string
      for i in 0 ..< rand(1 ..< 1000):
        body &= randomAsciiString()

      var
        pos: int
        encoded: string
      while true:
        let chunkLen = min(rand(1 ..< 4096), body.len - pos)
        encoded &= toHex(chunkLen)
        encoded &= "\r\n"
        encoded &= body[pos ..< pos + chunkLen]
        encoded &= "\r\n"
        pos += chunkLen
        if chunkLen == 0:
          break

      handleData.recvBuffer.add(encoded)

      # Add some junk the end
      handleData.recvBuffer.setLen(handleData.recvBuffer.len + rand(0 ..< 10))

      handleData.bytesReceived = handleData.recvBuffer.len

      let
        server = newServer(handler)
        clientSocket = 1.SocketHandle
        closingConnection = server.afterRecvHttp(
          clientSocket,
          handleData
        )
      if not closingConnection:
        let request = server.taskQueue.popFirst().request
        doAssert request.headers.headerContainsToken(
          "Transfer-Encoding", "chunked"
        )
        doAssert request.body == body
      server.close()

  block:
    echo "Content-Length"

    for i in 0 ..< iterations:
      let handleData = HandleData()

      var body: string
      for i in 0 ..< rand(1 ..< 1000):
        body &= randomAsciiString()

      handleData.recvBuffer.add("GET / HTTP/1.1\r\n")
      handleData.recvBuffer.add("Content-Length: " & $body.len & "\r\n")
      handleData.recvBuffer.add("\r\n")
      handleData.recvBuffer.add(body)

      # Add some junk the end
      handleData.recvBuffer.setLen(handleData.recvBuffer.len + rand(0 ..< 10))

      handleData.bytesReceived = handleData.recvBuffer.len

      block:
        # Not truncated
        let
          server = newServer(handler)
          clientSocket = 1.SocketHandle
          closingConnection = server.afterRecvHttp(
            clientSocket,
            handleData
          )
        if not closingConnection:
          let request = server.taskQueue.popFirst().request
          doAssert request.headers.headerContainsToken(
            "Content-Length", $body.len
          )
          doAssert request.body == body

      block:
        # Truncated
        handleData.recvBuffer.setLen(rand(0 ..< handleData.recvBuffer.len))

        handleData.bytesReceived = handleData.recvBuffer.len

        let
          server = newServer(handler)
          clientSocket = 1.SocketHandle
        discard server.afterRecvHttp(
          clientSocket,
          handleData
        )
        server.close()

block:
  echo "Fuzzing afterRecvWebSocket"

  proc handler(request: Request) =
    discard

  proc websocketHandler(
    websocket: WebSocket,
    event: WebSocketEvent,
    message: Message
  ) =
    discard

  block:
    echo "Frame header"

    var frameHeader = encodeFrameHeader(0x1, 0)
    frameHeader[1] = (frameHeader[1].uint8 or 0b10000000).char # Set masking bit

    for i in 0 ..< 1000:
      let handleData = HandleData()

      let
        v0 = rand(0 ..< frameHeader.len)
        v1 = rand(0 ..< 8)
      var frame = frameHeader
      frame[v0] = (frame[v0].uint8 xor (1.uint8 shl v1)).char
      frame.add("    ") # Empty mask

      handleData.recvBuffer.add(frame)

      # Add some junk the end
      handleData.recvBuffer.setLen(handleData.recvBuffer.len + rand(0 ..< 10))

      handleData.bytesReceived = handleData.recvBuffer.len

      let
        server = newServer(handler, websocketHandler)
        clientSocket = 1.SocketHandle
        websocket = WebSocket(server: server, clientSocket: clientSocket)

      server.websocketQueues[websocket] = initDeque[WebSocketUpdate]()
      server.websocketClaimed[websocket] = false

      let closingConnection = server.afterRecvWebSocket(
          clientSocket,
          handleData
        )
      if not closingConnection:
        if server.taskQueue.len > 0:
          let websocket = server.taskQueue.popFirst().websocket
          doAssert websocket.server == server
          doAssert websocket.clientSocket == clientSocket
      server.close()

  block:
    echo "Continuations"

    for i in 0 ..< 1:
      let handleData = HandleData()

      let
        server = newServer(handler, websocketHandler)
        clientSocket = 1.SocketHandle
        websocket = WebSocket(server: server, clientSocket: clientSocket)

      server.websocketQueues[websocket] = initDeque[WebSocketUpdate]()
      server.websocketClaimed[websocket] = false

      var combined: string

      # 1 or more continuations
      let numContinuations = rand(2 ..< 10)
      for j in 0 ..< numContinuations:
        var payload = randomAsciiString()

        combined &= payload

        let mask = [
          rand(0 .. 255).uint8,
          rand(0 .. 255).uint8,
          rand(0 .. 255).uint8,
          rand(0 .. 255).uint8
        ]

        # Mask the payload
        for i in 0 ..< payload.len:
          let j = i mod 4
          payload[i] = (payload[i].uint8 xor mask[j]).char

        var frame = encodeFrameHeader(
          if j == 0: 0x1 else: 0x0,
          payload.len
        )
        if j < numContinuations - 1:
          frame[0] = (frame[0].uint8 and 0b01111111).char # Clear fin
        frame[1] = (frame[1].uint8 or 0b10000000).char # Set masking bit
        frame.add(mask[0].char)
        frame.add(mask[1].char)
        frame.add(mask[2].char)
        frame.add(mask[3].char)
        frame.add(payload)

        handleData.recvBuffer.setLen(handleData.bytesReceived)

        handleData.recvBuffer.add(frame)

        handleData.bytesReceived = handleData.recvBuffer.len

        let closingConnection = server.afterRecvWebSocket(
            clientSocket,
            handleData
          )
        if closingConnection:
          doAssert false

      # The initial frame + continuations have been received

      let task = server.taskQueue.popFirst()

      doAssert task.websocket == websocket

      let update = server.websocketQueues[websocket].popFirst()

      doAssert update.event == MessageEvent
      doAssert update.message.kind == TextMessage
      doAssert update.message.data == combined
