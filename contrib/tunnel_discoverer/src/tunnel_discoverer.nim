import std/asyncdispatch, asyncnet, json, os, strutils, uri
from std/nativesockets import AF_UNIX, SOCK_STREAM, Protocol
import getdns

when not defined(posix): {.error: "This utility requires POSIX".}

var MAXHOSTNAMELEN {.importc, header: "<sys/param.h>".}: cint
proc getdomainname(name: ptr char; namelen: cint): cint {.importc, header: "<unistd.h>".}

proc getdomainname: string =
  ## Get the NIS domain name of current host.
  result = newString(MAXHOSTNAMELEN)
  if getdomainname(unsafeAddr result[0], cint result.len) != 0:
    raiseOSError(osLastError(), "getdomainname failed")
  for i, c in result:
    if c == '\0': result.setLen(i)
    break

proc checkError(r: getdns_return_t) =
  if r.isBad: quit($r, QuitFailure)

proc adminSocketUri(): Uri =
  var params = commandLineParams()
  case params.len
  of 0: return Uri(scheme: "unix", path: "/var/run/yggdrasil.sock")
  of 1: parseUri(params[0])
  else: quit("expected admin socket URI as a single argument", QuitFailure)

proc dialAdminSocket(uri: Uri): Future[AsyncSocket] {.async} =
  case uri.scheme
  of "unix", "":
    var sock = newAsyncSocket(
        domain = AF_UNIX,
        sockType = SOCK_STREAM,
         protocol = cast[Protocol](0),
        buffered = false)
    await connectUnix(sock, uri.path)
    return sock
  of "tcp":
    var
      port = Port parseInt(uri.port)
      sock = await dial(uri.hostname, port, buffered = false)
    return sock
  else:
    raise newException(ValueError, "invalid URI scheme for admin socket")

proc main =
  var context = getdns.newContext(true)
  context.setResolutionType(GETDNS_RESOLUTION_STUB)
  var
    serviceProtoName = "_yggdrasil_tunnel._tcp." & getdomainname()
    response: Dict
  checkError service_sync(context, serviceProtoName, nil, addr response)
  if response["status"].int != RESPSTATUS_GOOD:
    quit($response, QuitFailure)
  else:
    var
      adminUri = adminSocketUri()
      adminSock: AsyncSocket
    try:
      adminSock = waitFor dialAdminSocket(adminUri)
    except:
      quit("failed to connect to $1: $2" % [ $adminUri, getCurrentExceptionMsg()])
    for srvAddr in response["srv_addresses"]:
      var uri = Uri(
        scheme: "tcp",
        hostname: srvAddr["domain_name"].bindata.toFqdn,
        port: $srvAddr["port"].int)
      var req = %* { "keepalive": true, "request": "addPeer", "arguments": { "uri": $uri } }
      waitFor send(adminSock, $req & "\n")
      var
        resp = waitFor adminSock.recv(1024)
        js = parseJson(resp)
      stderr.writeLine(js["status"].getStr)
    close(adminSock)

main()
