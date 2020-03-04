# Tremor with Vector as an event sink

This is a simple example integration between tremor and vector
with vector as an event sink

## Scenario

We use file based vector sinks in this example. Vector has very flexible
support for file based log sinks allowing vector to be used for log data
transformation and storage.

Tremor is more focused on near real-time stream based sources and sinks.

By setting up a combined tremor and vector sidecar integrated over TCP sockets
we can leverage vector data sinks and tremor's scripting and query languages.

## Setup

We need to download and install tremor and vector and make sure we have
their servers / daemons on the system path:

```bash
$ cd /Code
$ git clone git@github.com:tremorio/vector
$ cd vector && cargo build
$ cd /Code
$ git clone git@github.com:wayfair-tremor/tremor-runtime
$ cd tremor-runtime && cargo build
$ export PATH=/Code/vector/target/debug/vector:/Code/tremor-runtime/target/debug/tremor-server:$PATH
```

## Configure Vector as a Sink

```toml

# Use a file based data sink
[sinks.out]
  type = "file"
  inputs = ["tcp"]
  path = "received-%Y-%m-%d.log"
  encoding = "ndjson"
  healthcheck = true 

# For debugging purposes
[sinks.console]
  type = "console"
  encoding = "json"
  inputs = [ "tcp" ]

# Use a tcp based data source
[sources.tcp]
  type = "socket"
  address = "0.0.0.0:8888"
  mode = "tcp"
  host_key = "host" # default
```

## Configure Tremor as a log event source 

```yaml
onramp:
  - id: source
    type: tcp
    preprocessors:
      - lines
    codec: json
    config:
      host: 127.0.0.1
      port: 8880

offramp:
  - id: vector
    type: tcp
    codec: json
    postprocessors:
      - lines
    config:
      host: "localhost"
      port: 8888

binding:
  - id: main
    links:
      '/onramp/source/{instance}/out': [ '/pipeline/logic/{instance}/in' ]
      '/pipeline/logic/{instance}/out': [ '/offramp/system::stdout/system/in', '/offramp/vector/{instance}/in' ]

mapping:
  /binding/main/01:
    instance: "01"
```

## Configure business logic

We setup a simple tremor script to validate the log data format and
distribute to vector for file-based storage. 

```trickle
select
  match event of
    case %{ present application, present date, present message } =>
      { "ok": merge event of { "host": system::hostname() } end }
    default => { "error": "invalid", "got": event }
  end
from in into out;
```

## Run vector and tremor side by side

Run vector in a terminal

```bash
$ vector -c etc/vector/vector.toml
```

Run tremor in a terminal

```bash
$ tremor-server -q etc/tremor/logic.trickle -c etc/tremor/tremor.yaml
```

## Results

We should see logs generated in the bash script being pushed to tremor
over a TCP socket via the netcat `nc` command. Tremor processes these
files through a simple query and distributes them to vector. Vector is
listening on a TCP socket and upon receiving events from Treor it persists
them to a file-based sink.

```text
Mar 04 14:02:09.320  INFO vector: Log level "info" is enabled.
Mar 04 14:02:09.321  INFO vector: Loading configs. path=["etc/vector/vector.toml"]
Mar 04 14:02:09.335  INFO vector: Vector is starting. version="0.9.0" git_version="v0.8.0-27-g1944ae9" released="Tue, 03 Mar 2020 13:21:51 +0000" arch="x86_64"
Mar 04 14:02:09.336  INFO vector::topology: Running healthchecks.
Mar 04 14:02:09.337  INFO vector::topology: Starting source "tcp"
Mar 04 14:02:09.337  INFO vector::topology::builder: Healthcheck: Passed.
Mar 04 14:02:09.337  INFO vector::topology::builder: Healthcheck: Passed.
Mar 04 14:02:09.337  INFO vector::topology: Starting sink "out"
Mar 04 14:02:09.338  INFO vector::topology: Starting sink "console"
Mar 04 14:02:09.338  INFO source{name=tcp type=socket}: vector::sources::util::tcp: listening. addr=0.0.0.0:8888
{"host":"127.0.0.1","message":"{\"error\":\"malformed\",\"got\":{\"application\":\"test\",\"date\":1583326934235095000,\"message\":\"demo\"}}","timestamp":"2020-03-04T13:02:14.258646Z"}
{"host":"127.0.0.1","message":"{\"error\":\"malformed\",\"got\":{\"application\":\"test\",\"date\":1583326935270284000,\"message\":\"demo\"}}","timestamp":"2020-03-04T13:02:15.282415Z"}
{"host":"127.0.0.1","message":"{\"error\":\"malformed\",\"got\":{\"application\":\"test\",\"date\":1583326936294948000,\"message\":\"demo\"}}","timestamp":"2020-03-04T13:02:16.305503Z"}
```
A file of the form `received-%Y-%M-%D.log` should now be available and filling with json
structured log events.

## Notes

No effort was made in this integration solution to tune vector or tremor.

For further information on [vector](https://vector.dev/) and [tremor](https://tremor.rs)
consult their respective web sites, documentation and references.

## Glossary

Vector uses the term `source` and `sink` for input to vector and outputs from vector.
Tremor uses the term `onramp` and `offramp` for ingress to tremor and egress from tremor.

In this integration we deployed vector and tremor as sidecars so that we can leverage
file based log storage in vector.
