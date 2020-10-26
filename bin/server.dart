import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:args/args.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

// For Google Cloud Run, set _hostname to '0.0.0.0'.
const _hostname = 'localhost';

void main(List<String> args) async {
  var parser = ArgParser()..addOption('port', abbr: 'p');
  var result = parser.parse(args);

  // For Google Cloud Run, we respect the PORT environment variable
  var portStr = result['port'] ?? Platform.environment['PORT'] ?? '8080';
  var port = int.tryParse(portStr);

  if (port == null) {
    stdout.writeln('Could not parse port value "$portStr" into a number.');
    // 64: command line usage error
    exitCode = 64;
    return;
  }

  var app = Router();
  final history = <String,Map>{};
  final clientAck = <String,Completer<Null>>{};

  app.get('/cgi-ssl/mpo_auth_reply.cgi', (Request request) async {
    final transId = request.url.queryParameters['transid'];
    return Response.ok('Return to testsuite');
  });

  app.post('/cgi-ssl/mpo_auth.cgi', (Request request) async {
    final transId = request.url.queryParameters['transid'];

    final map = json.decode(await request.readAsString());
    history[transId] = map;

    if(clientAck.containsKey(transId)) {
      clientAck[transId].complete();
    }

    return Response(204);
  });

  app.get('/request', (Request request) {
    return Response.ok(json.encode(history), headers: ContentType.json.parameters);
  });

  app.get('/request/<transId>', (Request request, String transId) async {
    final clientWait = request.url.queryParameters.containsKey('await');

    if(!history.containsKey(transId)) {
      // Await the value
      if(clientWait) {
        if(!clientAck.containsKey(transId)) {
          clientAck[transId] = Completer<Null>();
        }
        await clientAck[transId].future;
      }
      // Just try again later
      else {
        return Response(404, body: 'No such transaction yet.');
      }
    }

    return Response.ok(json.encode(history[transId]), headers: ContentType.json.parameters);
  });


  var handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(app.handler);

  var server = await io.serve(handler, _hostname, port);
  print('Serving at http://${server.address.host}:${server.port}');
}
