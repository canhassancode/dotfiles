# QA readiness: not mistaking warm-up for failure

Research for the gauntlet `qa` guard (`run.py`). Question: how should an external harness that starts a
system under test, waits for readiness, then drives it over HTTP, be designed so that first-request
warm-up latency, lazy compilation and cold-start 5xx/timeouts are never scored as product failures?

Every claim below carries the URL it came from. Where a source does **not** support a common belief, that
is stated rather than glossed.

---

## (a) Findings

### 1. Kubernetes: startup vs readiness vs liveness

Kubernetes separates "has it finished starting" from "can it serve" from "is it wedged", and the separation
exists precisely because conflating the first two produces false failures.

- Startup probes "verify whether the application within a container is started", and "If a startup probe is
  configured, Kubernetes does not execute liveness or readiness probes until the startup probe succeeds,
  allowing the application time to finish its initialization."
  <https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/>
- Why they exist: "Startup probes are useful for Pods that have containers that take a long time to come
  into service. Rather than set a long liveness interval, you can configure a separate configuration for
  probing the container as it starts up, allowing a time longer than the liveness interval would allow."
  The stated trigger is arithmetic: "If your container usually starts in more than `initialDelaySeconds +
  failureThreshold × periodSeconds`, you should specify a startup probe that checks the same endpoint as
  the liveness probe."
  <https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/>
- Readiness is explicitly about serving, and explicitly about warm-up: "Sometimes, applications are
  temporarily unable to serve traffic. This is useful when waiting for an application to perform
  time-consuming initial tasks, such as establishing network connections, loading files, and warming
  caches." Failure removes the Pod's address from the EndpointSlices — i.e. it withholds traffic rather
  than declaring a fault.
  <https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/>
- Depth is a documented choice, not an accident: "When your app has a strict dependency on back-end
  services, you can implement both a liveness and a readiness probe. The liveness probe passes when the app
  itself is healthy, but the readiness probe additionally checks that each required back-end service is
  available. This helps you avoid directing traffic to Pods that can only respond with error messages."
  <https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/>
- Consecutive-success semantics. `successThreshold`: "Minimum consecutive successes for the probe to be
  considered successful after having failed. Defaults to 1. Must be 1 for liveness and startup probes."
  `failureThreshold` defaults to 3; `periodSeconds` defaults to 10; **`timeoutSeconds` defaults to 1
  second, minimum 1**.
  <https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/>,
  <https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/>

Read the constraint carefully, because it is the load-bearing one for us: a *startup* gate is allowed one
success, because its budget is spent in `failureThreshold × periodSeconds`, not in repetition. A
*readiness* gate — the thing that decides "traffic may now be judged against this" — is the only probe
Kubernetes permits to demand more than one consecutive success. That is exactly the right shape for a QA
harness, which is a readiness consumer, not a restart controller.

### 2. Health-check depth: shallow vs deep

- Azure's Health Endpoint Monitoring pattern: "The health monitoring code in the application might also run
  other checks to determine: The availability and response time of cloud storage or a database. The status
  of other resources or services that the application uses." It also warns that status code alone is thin —
  "Checking the status code is the minimum implementation of this pattern... But a code supplies little
  information about the operations, trends, and possible upcoming issues" — and recommends "Checking the
  content of the response to detect errors, even when the status code is 200 (OK)."
  <https://learn.microsoft.com/en-us/azure/architecture/patterns/health-endpoint-monitoring>
- Azure also recommends **more than one endpoint**: "Determine the number of endpoints to expose for an
  application. One approach is to expose at least one endpoint for the core services that the application
  uses and another for lower-priority services... Also consider exposing extra endpoints. You can expose
  one for each core service to increase monitoring granularity." And: "To ensure that your application
  works correctly for all customers, run tests against all the service instances that customers use."
  <https://learn.microsoft.com/en-us/azure/architecture/patterns/health-endpoint-monitoring>
- Azure warns the check must fit the monitor's timeout: "Performing excessive processing during the check
  can overload the application... The processing time might also exceed the timeout of the monitoring
  system. As a result, the system might mark the application as unavailable."
  <https://learn.microsoft.com/en-us/azure/architecture/patterns/health-endpoint-monitoring>
- Google SRE distinguishes three backend states, and the middle one is our failure mode: **Healthy** ("The
  backend task has initialized correctly and is processing requests"), **Refusing connections** ("The
  backend task is unresponsive. This can happen because the task is starting up or shutting down"), and
  **Lame duck** ("The backend task is listening on its port and can serve, but is explicitly asking clients
  to stop sending requests"). Listening is not serving; readiness is signalled, not inferred.
  <https://sre.google/sre-book/load-balancing-datacenter/>
- The Amazon Builders' Library article *Implementing health checks* runs the argument the other way for
  production: it distinguishes liveness checks, local (on-box) health checks and dependency health checks,
  and warns that a dependency health check without fail-open turns a soft dependency into a hard one and
  propagates a cascading failure; Amazon teams therefore tend to restrict fast-acting load-balancer health
  checks to local health checks and let centralised systems react to deeper ones.
  <https://aws.amazon.com/builders-library/implementing-health-checks/>
  (Caveat on sourcing: that page now redirects to `builder.aws.com` and renders client-side, so the above
  is a paraphrase reconstructed from search excerpts rather than a verbatim quotation. Treat the wording as
  mine and the position as theirs.)

**The two sources do not conflict; the contexts differ.** AWS is warning about a *production load balancer*
that pulls capacity out of service when a dependency blips — there, deep checks amplify outages. A QA gate
has no capacity to pull and no blast radius: it wants the strongest possible statement that the system can
really serve. Depth is right for us and wrong for a fast-acting LB. Nothing in either source supports
"shallow is safer" as a universal.

### 3. Warm-up and lazy build in dev servers

**SST v3 live lambda.** The published docs describe the bridge but say nothing about build-on-invoke: a
stub Lambda replaces the real function, the local machine connects over AppSync Events via WebSocket, the
stub publishes the request payload as an event, the local client executes and publishes the response.
<https://sst.dev/docs/live/>. `--mode=mono` is a UI choice only: "this'll spawn child processes. But
instead of a tabbed UI it'll show their outputs in a single stream" — versus `--mode=basic`, which "will
only deploy your app and run your functions". <https://sst.dev/docs/reference/cli/>

The build behaviour is only in the source, and it is unambiguous. `cmd/sst/mosaic/aws/function.go` handles
a `bridge.MessageInit` — the signal that a *new* remote execution environment has appeared — by calling
`startWorker`, whose first act is `getBuildOutput(functionID)`, which calls
`input.project.Runtime.Build(ctx, target)` if that function ID is not already in the `builds` map:

```go
getBuildOutput := func(functionID string) *runtime.BuildOutput {
    build := builds[functionID]
    if build != nil { return build }
    target, _ := targets[functionID]
    build, err := input.project.Runtime.Build(ctx, target)
```

<https://raw.githubusercontent.com/sst/sst/dev/cmd/sst/mosaic/aws/function.go>

So the esbuild `Build` for a function happens **inside the first invocation of that function**, per
function, and the cache is per `functionID` — warming `/api/health` warms nothing about the authorizer.
The `builds` map is also reset on every `project.CompleteEvent`, so a redeploy re-arms every cold start.
The runtime interface documents the lazy variant explicitly: "ShouldRunEagerly controls whether workers are
started immediately after a rebuild or lazily on first invocation... workers are stopped and marked as
needing rebuild, but only actually start when invoked."
<https://raw.githubusercontent.com/sst/sst/dev/pkg/runtime/runtime.go>

Note also that `startWorker` is called from a single `select` loop over one message channel — worker
startup, and therefore the build, is serialised. Concurrent first invocations of the same function queue
behind one another. That is a plausible mechanism for "2 of 5 concurrent authorizer invocations stalled",
and it is a *harness-visible* property, not a product bug. Nothing in the SST docs documents a concurrency
limit or a first-invoke latency budget; do not expect one.

**Vite.** Lazy transform is the design: "Source code (your application code that changes frequently) is
served on-demand over native ESM... The browser loads only what it needs for the current page, and Vite
transforms each file as it's requested." <https://vite.dev/guide/why>. The remedy is an explicit priming
list: `server.warmup` "Warm up files to transform and cache the results in advance", with `clientFiles`
and `ssrFiles`, which "improves the initial page load during server starts and prevents transform
waterfalls" — plus the cost warning, "Make sure to only add files that are frequently used to not overload
the Vite dev server on startup." <https://vite.dev/config/server-options>

**Next.js.** `next dev` "Starts Next.js in development mode with Hot Module Reloading, error reporting, and
more", and dev output goes to `.next/dev`. <https://nextjs.org/docs/app/api-reference/cli/next>. The CLI
reference does **not** state that routes are compiled on first visit — the on-demand-compilation behaviour
is widely observed but is not something I found asserted in the current primary docs. Do not cite it as
documented.

**AWS Lambda + API Gateway.** Cold starts are documented and bounded loosely: "the first two steps of
downloading the code and setting up the environment are frequently referred to as a 'cold start'... Cold
starts typically occur in under 1% of invocations. The duration of a cold start varies from under 100 ms to
over 1 second. In general, cold starts are typically more common in development and test functions than
production workloads." Critically for the observed 500: "The `Init` phase is limited to 10 seconds. If all
three tasks do not complete within 10 seconds, Lambda retries the `Init` phase at the time of the first
function invocation with the configured function timeout."
<https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtime-environment.html>

API Gateway REST integration timeout: "Integration timeout for Regional APIs — 50 milliseconds - 29 seconds
for all integration types, including Lambda, Lambda proxy, HTTP, HTTP proxy, and AWS integrations", with
the footnote "You can raise the integration timeout to greater than 29 seconds, but this might require a
reduction in your Region-level throttle quota for your account." Edge-optimised APIs cannot be raised.
<https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-execution-service-limits-table.html>

Authorizer caching: `authorizerResultTtlInSeconds` — "The TTL in seconds of cached authorizer results. If
it equals 0, authorization caching is disabled... If this field is not set, the default value is 300. The
maximum value is 3600, or 1 hour."
<https://docs.aws.amazon.com/apigateway/latest/api/API_CreateAuthorizer.html>. The cache key is the
identity source(s): "When multiple identity sources are defined, they are all used to derive the
authorizer's cache key, with the order preserved."
<https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-use-lambda-authorizer.html>

**On the "10s Lambda authorizer timeout":** I could not find a documented 10-second authorizer execution
timeout in the API Gateway quotas or authorizer pages. What *is* documented at 10 seconds is Lambda's
`Init` phase limit (above). If a first authenticated request 500s at ~10s while the login 504s at ~29s,
the documented explanation is a 29s integration timeout on the integration path and an Init-phase
constraint on the authorizer path — not a separate authorizer quota. Do not build config around a number
the docs do not state.

### 4. Wait strategies as prior art

Testcontainers is the closest existing thing to what `qa_guard` does, and its API is instructive because
every knob we are missing is a knob it has.

- Java: `Wait.forHttp("/")` with `.forStatusCode(200)`, `.forStatusCodeMatching(it -> it >= 200 && it <
  300)`, `.forResponsePredicate(...)`; also `Wait.forLogMessage`, `Wait.forHealthcheck()`,
  `Wait.forSuccessfulCommand()`, a composite `WaitAllStrategy`, and `withStartupTimeout()`. The default is
  "Testcontainers will wait for up to 60 seconds for the container's first mapped network port".
  <https://java.testcontainers.org/features/startup_and_waits/>
- Node: `Wait.forListeningPorts()`, `Wait.forLogMessage()`, `Wait.forHealthCheck()` ("Explicitly wait until
  the container's health check is successful"), `Wait.forHttp()` with `forStatusCode` /
  `forStatusCodeMatching` / `forResponsePredicate`, `Wait.forSuccessfulCommand()` ("Wait until a shell
  command returns a successful exit code"), `Wait.forAll()` for composites, `withStartupTimeout()` and
  `withDeadline()`; default 60 s. Testcontainers prefers the container's health check when one exists and
  falls back to listening ports only when it does not.
  <https://node.testcontainers.org/features/wait-strategies/>

Docker's `HEALTHCHECK` encodes the startup-vs-steady-state split directly: `--interval` (30s),
`--timeout` (30s), `--start-period` (0s), `--start-interval` (5s), `--retries` (3), with three states —
`starting`, `healthy`, `unhealthy` — and the key semantic that during the start period "failures do not
count towards the retries". <https://docs.docker.com/reference/dockerfile/>

Compose consumes that: `depends_on` with `condition: service_healthy` "Specifies that a dependency is
expected to be 'healthy' (as indicated by `healthcheck`) before starting a dependent service", alongside
`service_started` and `service_completed_successfully`.
<https://docs.docker.com/reference/compose-file/services/>

Two things to steal: **a failure inside the start window is not a failure**, and **the ready predicate is
richer than a status class**.

### 5. Hermetic testing

- Google's "Hermetic Servers" post is the canonical statement of the principle — a server packaged so it
  can be brought up in isolation, without external dependencies, for end-to-end and performance testing.
  (The post body did not render for retrieval; the surrounding discussion supports the isolation and
  performance-regression uses.) <https://testing.googleblog.com/2012/10/hermetic-servers.html>
- Fowler, *Eradicating Non-Determinism in Tests*, gives the two operative rules. On asynchrony: "Never use
  bare sleeps to wait for asynchonous responses: use a callback or polling", with a small polling interval
  and a generous limit — "you can set the `pollingInterval` to a pretty small value... set the `waitLimit`
  very high, which minimizes the chance of hitting it." On external systems: use a Test Double, and pin it
  with contract tests, because "How can we be sure that the double behaves in the same way that remote
  system does?" And on containment: "Place any non-deterministic test in a quarantined area."
  <https://martinfowler.com/articles/nonDeterminism.html>
- Google's own rerun policy is narrow, not blanket: "Our rerun mechanism is only used for tests that are
  marked as flaky or when users specifically request it."
  <https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html>

The principle that matters here: **a verdict must not depend on the warm state of anything.** If the only
way a criterion passes is "the server happened to have compiled that route already", the test is
non-deterministic and its green is worth nothing — and, symmetrically, its red is worth nothing either.

### 6. Prime before measuring

The pattern is real and is implemented by every layer that has a cold path:

- IIS Application Initialization states the problem plainly: "A common problem faced by website
  administrators is the need to perform initialization tasks and 'warm up' tasks for a web application.
  Larger and more complex web applications may need to perform lengthy startup processing, prime in-memory
  caches, generate content, etc... prior to serving the first HTTP request." The mechanism is a synthetic
  request — `preloadEnabled="true"` "tells IIS 8.0 that it sends a 'fake' request to the application when
  the associated application pool starts up" — plus `<applicationInitialization>` with
  `initializationPage`, and an `APP_WARMING_UP` server variable that is "set by IIS to a value of '1' when
  application initialization is active", used to serve a static splash page meanwhile.
  <https://learn.microsoft.com/en-us/iis/get-started/whats-new-in-iis-8/iis-80-application-initialization>
- Vite's `server.warmup` is the same idea for transforms. <https://vite.dev/config/server-options>
- Lambda's two answers: provisioned concurrency "pre-initializes execution environments, reducing cold
  starts" — "a function with a provisioned concurrency of 6 has 6 execution environments pre-warmed"
  (<https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtime-environment.html>) — and SnapStart, which
  snapshots the initialised environment at publish time and resumes from it, "improving startup latency";
  the docs recommend provisioned concurrency "if your application has strict cold start latency
  requirements that can't be adequately addressed by SnapStart".
  <https://docs.aws.amazon.com/lambda/latest/dg/snapstart.html>

**Where the sources are weaker than the folklore.** I could not find, in k6's ramping-vus page or JMeter's
best-practices page, a documented instruction to discard warm-up traffic from results. The k6 page
describes stages mechanically only
(<https://grafana.com/docs/k6/latest/using-k6/scenarios/executors/ramping-vus/>) and JMeter's best
practices does not mention warm-up, JIT or discarding early samples
(<https://jmeter.apache.org/usermanual/best-practices.html>). The nearest documented *mechanism* is k6's
`tagWithCurrentStageProfile`, which tags metrics with a `stage_profile` of `ramp-up`, `steady` or
`ramp-down` so thresholds can be scoped to one of them
(<https://grafana.com/docs/k6/latest/using-k6/tags-and-groups/>). So: "separate warm-up from measurement"
is well supported as an *engineering* pattern by IIS/Vite/Lambda, and is only *tooling-supported*, not
*doctrinally stated*, in the load-test tools. Cite it as the former.

### 7. Retry semantics

- RFC 9110 §9.2.2: "A request method is considered 'idempotent' if the intended effect on the server of
  multiple identical requests with that method is the same as the effect for a single such request." GET,
  HEAD, PUT, DELETE, OPTIONS and TRACE are idempotent; POST is not. The automatic-retry licence is
  deliberately narrow: "A client MAY automatically repeat a request with a method idempotent if that
  request fails due to a communication failure that occurs before the response is received."
  <https://www.rfc-editor.org/rfc/rfc9110.html#name-idempotent-methods>
- AWS SDK retry guidance classifies errors as transient, throttling or non-retryable; transient includes
  "any HTTP 500, 502, 503, or 504 without a recognized error code" and I/O failures, retried with
  exponential backoff plus full jitter and a token-bucket retry quota so that "your application fails fast
  instead of waiting through retries that are unlikely to succeed". Default max attempts is 3.
  <https://docs.aws.amazon.com/sdkref/latest/guide/feature-retry-behavior.html>
- Google Cloud Storage's retry strategy makes the idempotency condition explicit: retryable response codes
  are "HTTP `408`, `429`, and `5xx` response codes, Socket timeouts and TCP disconnects"; operations are
  classified always idempotent, conditionally idempotent (only with an `ifGenerationMatch` /
  `IfMetagenerationMatch` precondition) or never idempotent, and the listed anti-patterns include
  "unconditionally retrying non-idempotent operations".
  <https://cloud.google.com/storage/docs/retry-strategy>

Read the licence precisely. RFC 9110 permits an automatic repeat when the *response was never received* —
not when a 504 came back. A 504 from API Gateway is a response. None of these sources sanction a
*judge* retrying a request whose failure is the thing being judged; all three are guidance for a *client*
whose goal is to succeed. That distinction is the whole answer to "should the relay retry".

---

## (b) The fundamentals

1. **Starting is not readiness, and readiness is not health.** Three questions, three budgets. Kubernetes
   physically separates them and suppresses the other two while the first runs. A harness that has one
   `wait_for` is answering one question and pretending it answered three.
2. **A failure inside the start window is not a failure.** Docker's `--start-period` and Kubernetes'
   startup probe both encode this. Whatever happens before the readiness gate opens must be uncountable.
3. **Readiness is asserted, not inferred.** "Listening" is Google SRE's *refusing connections* or *lame
   duck*, not *healthy*. "Answers below 500" is a weaker signal still: a dev server that has booted but not
   compiled a route answers 404, and 404 is below 500.
4. **A ready predicate must be at least as expensive as the thing it licenses.** Azure: a status code
   "supplies little information"; check the body. If the criterion under test crosses a database, an
   authorizer and a lambda, a probe that crosses a static file has licensed nothing.
5. **One readiness target proves one code path.** Azure recommends an endpoint per core service. In SST,
   the build cache is keyed per `functionID`, so it is literally one endpoint per function.
6. **Prime before you measure.** IIS sends a fake request; Vite pre-transforms; Lambda pre-initialises.
   The priming traffic is real traffic against the real system, and its outcome is *not evidence*.
7. **The measurement window must be steady-state, and its boundary must be explicit.** k6's
   `stage_profile` tag exists so a threshold can name which phase it judges. A harness with no phase
   boundary is asserting that its first request and its hundredth are the same experiment. They are not.
8. **A judge does not retry.** Retry guidance exists for clients pursuing success. A harness pursuing
   truth that retries a 504 has converted a product failure into a pass and destroyed the evidence.
9. **Hermeticity is the repo's obligation, determinism is the harness's.** Fowler and the hermetic-servers
   principle put the burden of "no external warm state" on the system under test. The harness's job is to
   refuse to render a verdict until the repo's declared contract is met, and to say *unverified* rather
   than *failed* when it is not.
10. **Distinguish "the environment did not deliver a system" from "the system failed the criterion".**
    These are different exit codes because they route to different humans. `run.py` already knows this
    (exit 2 vs exit 1); the shape below just widens the set of conditions that earn exit 2.

---

## (c) Recommendations for `run.py` and the `serve` config

### The bug that made brushfeed unpassable

`wait_for` is at `run.py:362`:

```python
urllib.request.urlopen(url, timeout=1).close()
```

**One second per probe attempt.** A `ready` URL that fronts a cold SST function cannot answer inside one
second — the esbuild `Build` runs inside that first invocation
(<https://raw.githubusercontent.com/sst/sst/dev/cmd/sst/mosaic/aws/function.go>). Every attempt raises a
socket timeout, is swallowed as `OSError`, and the loop spins until `serve.timeout` expires. Given that,
`ready` *had* to point at something static for the guard to ever go green. The config was not merely
careless; it was the only shape that could pass. Compare Kubernetes' `timeoutSeconds`, which also defaults
to 1 but is a per-probe knob you are expected to raise
(<https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/>), and Testcontainers'
60 s default startup timeout (<https://java.testcontainers.org/features/startup_and_waits/>).

Second defect, same function: `if response.code < 500: return True`. A 404 passes. A 401 passes. A dev
server serving its "compiling…" placeholder passes. Testcontainers makes you say `forStatusCode(200)` or a
predicate for exactly this reason (<https://node.testcontainers.org/features/wait-strategies/>).

Third: one success ends the wait. Docker requires consecutive successes via `--retries`
(<https://docs.docker.com/reference/dockerfile/>); Kubernetes lets readiness — and only readiness — demand
`successThreshold > 1`
(<https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/>).

### Proposed `serve` shape

```json
"serve": {
  "run": "pnpm dev",
  "url": "http://127.0.0.1:4321/",
  "startup": 300,
  "ready": [
    { "url": "http://127.0.0.1:4321/api/health", "expect": 200, "contains": "\"db\":\"ok\"", "timeout": 45 }
  ],
  "warmup": [
    { "method": "POST", "path": "/api/auth/login", "body": "@.gauntlet/warmup/login.json", "timeout": 90 },
    { "method": "GET",  "path": "/api/me",                                                  "timeout": 90 }
  ],
  "successes": 2,
  "interval": 2
}
```

Field by field, and why:

- **`startup`** (seconds, default 60) replaces `timeout`. It is the *start-period* budget, in Docker's
  sense: everything that happens inside it is uncountable. Name it `startup`, not `timeout`, so it reads as
  a phase and not as a per-request limit — the current name is what invited the 1 s probe to hide under it.
- **`ready` becomes a list, and becomes required.** Defaulting it to `serve.url` is the trap that fired:
  the front door of a full-stack app is the one route most likely to be static. When `serve` is present and
  `ready` is absent, that should be exit 2 with a message, not a silent fallback. Normalise a bare string
  to `{"url": s, "expect": 200}` in one line — that keeps existing configs loading while *tightening*
  rather than loosening the predicate.
- **`ready[].expect`** — an integer or list of integers, default `200`. Not "below 500". Testcontainers'
  `forStatusCode` is the model.
- **`ready[].contains`** — optional substring of the body. Azure's "checking the content of the response to
  detect errors, even when the status code is 200". This is what makes a health endpoint's dependency
  claims checkable rather than decorative: `{"db":"ok","auth":"ok"}`.
- **`ready[].timeout`** — per-attempt timeout, default **15 s**, not 1 s. Set it above the SUT's own cold
  path but below the gateway limit you are trying not to trip: for an SST repo, comfortably above an
  esbuild build and below 29 s
  (<https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-execution-service-limits-table.html>).
- **`interval`** (default 2 s) — the poll period. Fowler: small interval, generous limit
  (<https://martinfowler.com/articles/nonDeterminism.html>). 0.2 s against a 45 s endpoint is pointless
  hammering; 2 s is fine.
- **`successes`** (default 2) — consecutive successes required per target, applied *after* the first
  success. One warm answer can be luck; two consecutive cannot be the first-invoke build, because the build
  is cached after the first
  (<https://raw.githubusercontent.com/sst/sst/dev/cmd/sst/mosaic/aws/function.go>). Do not go above 3;
  beyond that you are buying nothing and paying wall-clock.
- **`warmup`** — an ordered list of requests issued **after** all `ready` targets are satisfied and
  **before** the QA script runs. This is the IIS `preloadEnabled` fake request, generalised. Rules:
  - Sent to `serve.url` **directly, not through the relay** — warm-up must not contribute to wire
    evidence, or the relay's "0 requests is red" check stops meaning "the script proved something".
  - **No `expect`.** A warm-up request's status is not evidence of anything; a 401 from an unauthenticated
    warm-up of `/api/me` is a perfectly good warm-up. The only outcome that matters is "the function
    built".
  - Sequential, not concurrent — SST serialises worker start behind one channel loop, so parallel
    warm-up buys nothing and makes the timeouts interact.
  - A warm-up that times out is exit 2 (environment), never exit 1 (criterion). It means the repo's serve
    cannot reach steady state, which is the local-development gap the README already names.

Phase separation in `qa_guard`, then, is: **start** (`serve.run`, nothing counted) → **ready** (`ready[]`,
`successes` consecutive each, failure = exit 2) → **warm-up** (`warmup[]`, off-relay, failure = exit 2) →
**verdict** (QA script through the relay, failure = exit 1). Four phases, three of which can only ever
produce an environment verdict. The product is only ever judged in the fourth.

### Should the relay ever retry? No.

Not once, not for GETs, not on 504. Three reasons, in decreasing order of force:

1. It destroys the evidence the guard exists to collect. The relay's whole job (README: "wire evidence —
   the one proof of 'against the running system' a stage cannot author") is to be an honest witness. A
   witness that re-runs the experiment until it likes the answer is not a witness.
2. RFC 9110's automatic-repeat licence covers "a communication failure that occurs before the response is
   received" (<https://www.rfc-editor.org/rfc/rfc9110.html#name-idempotent-methods>). A 504 *is* a
   received response. The retry guidance that does cover 5xx — AWS SDK
   (<https://docs.aws.amazon.com/sdkref/latest/guide/feature-retry-behavior.html>), GCS
   (<https://cloud.google.com/storage/docs/retry-strategy>) — is written for clients trying to succeed,
   and both attach it to idempotency conditions the harness cannot evaluate for an arbitrary product API.
3. The relay does not know which method is idempotent *in this product*. GCS's "conditionally idempotent"
   category exists precisely because the method verb is not sufficient.

Where retry *is* legitimate: inside `ready` polling (that is what polling is) and inside `warmup` (nothing
is being judged). Both are already outside the relay. Keep it that way.

### Two smaller relay fixes that follow from the same principle

- `RelayHandler.relay` returns a synthesised **502** when the upstream is unreachable
  (`run.py:419`). A QA script that checks status codes will read that as a product 502. Make the harness's
  own failures unmistakable: use a status the product will not plausibly emit (`599`) *and* set a
  `x-gauntlet-relay-error` header, and count it separately from product responses in the result JSON.
- The relay's upstream timeout is a hardcoded 60 s (`run.py:417`). Make it `serve.requestTimeout`
  (default 60). For an API Gateway-fronted SUT you want it above 29 s so that a genuine gateway 504 arrives
  as a 504 from the product rather than as a relay error — the distinction between "the product timed out"
  and "the harness gave up" is the entire point.

### What is the repo's responsibility, not the harness's

The README already asserts the right principle ("A repo without an honest `serve` is a repo with a
local-development gap"). Make it concrete, because brushfeed shows the current wording is not actionable
enough:

- **The repo owes a steady state, not just a process.** Either `serve.run` reaches it by itself (e.g. a
  pre-build step before `sst dev`, or `sst dev` plus a script that invokes each function once), or the repo
  declares the priming traffic in `serve.warmup`. Both are hermetic-server work in Google's sense
  (<https://testing.googleblog.com/2012/10/hermetic-servers.html>); neither is the harness guessing.
- **The repo owes a deep `/health`.** Kubernetes' readiness-with-dependencies shape
  (<https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/>) and Azure's
  per-service endpoints
  (<https://learn.microsoft.com/en-us/azure/architecture/patterns/health-endpoint-monitoring>). For a
  serverless repo this means the health route must itself be a Lambda behind the same gateway, and there
  should be a second `ready` target behind the authorizer, because the authorizer is a separate function
  with a separate cold start.
- **The repo owes credentials for the warm-up.** Warming an authenticated path requires a token; the README
  already tells repos to record "auth without email" in `CLAUDE.md`. Add: and to make it scriptable.
- **The harness owes only:** the phase separation, honest exit codes, per-phase budgets, and never
  laundering a cold start into a verdict — in either direction. Note the symmetry: the current design can
  fail a good product on a cold start, and a naive fix (retry until green) would pass a bad one. The fix is
  the phase boundary, not leniency.

### What none of the sources support

- That "answers below 500" is a readiness signal. Nothing says this. Testcontainers, Docker and Kubernetes
  all make you state the predicate.
- That a test harness may retry an assertion request. No cited source endorses it; Google reruns only
  already-quarantined tests
  (<https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html>), and Fowler quarantines
  rather than re-runs (<https://martinfowler.com/articles/nonDeterminism.html>).
- That load-testing tools document discarding warm-up samples. k6's ramping-vus page and JMeter's best
  practices do not. The pattern is supported by IIS, Vite and Lambda instead; cite those.
- That SST documents build-on-first-invoke, a first-invoke latency budget, or a live-lambda concurrency
  limit. It does not — that is source-derived
  (<https://raw.githubusercontent.com/sst/sst/dev/cmd/sst/mosaic/aws/function.go>) and could change.
- That API Gateway imposes a 10-second Lambda authorizer timeout. Not in the quotas table
  (<https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-execution-service-limits-table.html>)
  nor the authorizer page. The documented 10 seconds is Lambda's `Init` phase limit
  (<https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtime-environment.html>).
- That deep health checks are universally good. AWS's *Implementing health checks* argues the opposite for
  fast-acting load balancers (<https://aws.amazon.com/builders-library/implementing-health-checks/>). The
  depth recommendation here is scoped to a QA gate, which has no traffic to withhold.
