# go-logql

A pure Go query builder for [Grafana Loki's LogQL](https://grafana.com/docs/loki/latest/query/) query language.

- **Fluent, immutable builder pattern** (like [squirrel](https://github.com/Masterminds/squirrel) for SQL)
- **Zero external dependencies** — only the Go standard library
- **Generates LogQL strings only** — bring your own HTTP client
- **Safe for concurrent use** — every builder method returns a new instance

## Installation

```bash
go get github.com/apoorvgarg/go-logql
```

## Quick Start

```go
package main

import (
    "fmt"
    "time"

    logql "github.com/apoorvgarg/go-logql"
)

func main() {
    q := logql.NewLogQuery().
        Eq("job", "api").
        Eq("env", "prod").
        LineContains("error")

    fmt.Println(q.String())
    // {job="api", env="prod"} |= "error"

    m := logql.Rate(q, 5*time.Minute).
        Sum().
        By("job", "instance")

    fmt.Println(m.String())
    // sum by (job, instance) (rate({job="api", env="prod"} |= "error" [5m]))
}
```

## Usage

### Log Queries

#### Stream Selectors

```go
q := logql.NewLogQuery().
    Eq("job", "api").          // {job="api"}
    Neq("env", "dev").         // {env!="dev"}
    Re("instance", "10\\..*"). // {instance=~"10\..*"}
    Nre("method", "OPTIONS")   // {method!~"OPTIONS"}
```

#### Line Filters

```go
q := logql.NewLogQuery().
    Eq("job", "api").
    LineContains("error").       // |= "error"
    LineNotContains("debug").    // != "debug"
    LineMatch("error|warn").     // |~ "error|warn"
    LineNotMatch("trace|debug")  // !~ "trace|debug"
```

#### Parsers

```go
// JSON parser
q := logql.NewLogQuery().Eq("job", "api").JSON()
// {job="api"} | json

// JSON with specific fields
q = logql.NewLogQuery().Eq("job", "api").JSON("status", "method")
// {job="api"} | json status, method

// Logfmt parser
q = logql.NewLogQuery().Eq("job", "api").Logfmt()
// {job="api"} | logfmt

// Regexp parser
q = logql.NewLogQuery().Eq("job", "api").Regexp(`(?P<method>\w+) (?P<path>\S+)`)
// {job="api"} | regexp "(?P<method>\w+) (?P<path>\S+)"

// Pattern parser
q = logql.NewLogQuery().Eq("job", "api").Pattern("<method> <path> <status>")
// {job="api"} | pattern "<method> <path> <status>"

// Unpack
q = logql.NewLogQuery().Eq("job", "api").Unpack()
// {job="api"} | unpack
```

#### Label Filters

```go
q := logql.NewLogQuery().
    Eq("job", "api").
    JSON().
    LabelEqual("level", "error").     // | level == "error"
    LabelNotEqual("method", "GET").   // | method != "GET"
    LabelGreater("status", "400").    // | status > 400
    LabelGreaterEq("status", "400"). // | status >= 400
    LabelLess("duration", "5s").      // | duration < 5s
    LabelLessEq("duration", "10s").  // | duration <= 10s
    LabelRe("method", "GET|POST").    // | method =~ "GET|POST"
    LabelNre("path", "/health.*")     // | path !~ "/health.*"
```

#### Formatting and Pipeline Stages

```go
q := logql.NewLogQuery().
    Eq("job", "api").
    JSON().
    LineFormat("{{.msg}}").              // | line_format "{{.msg}}"
    LabelFormatEntry("dst", "src").      // | label_format dst=src
    Drop("internal_id", "trace_id").     // | drop internal_id, trace_id
    Keep("level", "msg").                // | keep level, msg
    Decolorize()                         // | decolorize
```

### Immutability

Every builder method returns a new instance. The original is never modified:

```go
base := logql.NewLogQuery().Eq("job", "api").Eq("env", "prod")

errors := base.LineContains("error")
warnings := base.LineContains("warning")

fmt.Println(base.String())     // {job="api", env="prod"}
fmt.Println(errors.String())   // {job="api", env="prod"} |= "error"
fmt.Println(warnings.String()) // {job="api", env="prod"} |= "warning"
```

### Metric Queries

#### Range Aggregations

```go
q := logql.NewLogQuery().Eq("job", "api")

logql.Rate(q, 5*time.Minute)            // rate({job="api"} [5m])
logql.CountOverTime(q, 1*time.Hour)      // count_over_time({job="api"} [1h])
logql.BytesRate(q, 5*time.Minute)        // bytes_rate({job="api"} [5m])
logql.BytesOverTime(q, 1*time.Hour)      // bytes_over_time({job="api"} [1h])
logql.AbsentOverTime(q, 5*time.Minute)   // absent_over_time({job="api"} [5m])
logql.FirstOverTime(q, 5*time.Minute)    // first_over_time({job="api"} [5m])
logql.LastOverTime(q, 5*time.Minute)     // last_over_time({job="api"} [5m])
```

#### Unwrap Range Aggregations

These require an `| unwrap <label>` stage in the log query:

```go
q := logql.NewLogQuery().Eq("job", "api").JSON().Unwrap("latency_ms")

logql.SumOverTime(q, 5*time.Minute)      // sum_over_time({...} | json | unwrap latency_ms [5m])
logql.AvgOverTime(q, 5*time.Minute)      // avg_over_time(...)
logql.MaxOverTime(q, 5*time.Minute)      // max_over_time(...)
logql.MinOverTime(q, 5*time.Minute)      // min_over_time(...)
logql.StddevOverTime(q, 5*time.Minute)   // stddev_over_time(...)
logql.StdvarOverTime(q, 5*time.Minute)   // stdvar_over_time(...)
logql.QuantileOverTime(0.95, q, 5*time.Minute) // quantile_over_time(0.95, ...)
```

#### Aggregation Operators

```go
q := logql.NewLogQuery().Eq("job", "api")
r := logql.Rate(q, 5*time.Minute)

r.Sum()                        // sum (rate(...))
r.Avg()                        // avg (rate(...))
r.Min()                        // min (rate(...))
r.Max()                        // max (rate(...))
r.Count()                      // count (rate(...))
r.Stddev()                     // stddev (rate(...))
r.Stdvar()                     // stdvar (rate(...))
r.TopK(5)                      // topk(5, rate(...))
r.BottomK(3)                   // bottomk(3, rate(...))
r.Sort()                       // sort(rate(...))
r.SortDesc()                   // sort_desc(rate(...))
```

#### Grouping and Offset

```go
r := logql.Rate(
    logql.NewLogQuery().Eq("job", "api"),
    5*time.Minute,
)

r.Sum().By("job", "instance")       // sum by (job, instance) (rate(...))
r.Sum().Without("instance")         // sum without (instance) (rate(...))
r.Offset(1 * time.Hour)             // rate(...) offset 1h
```

### Binary Expressions

```go
errors := logql.Rate(
    logql.NewLogQuery().Eq("job", "api").LineContains("error"),
    5*time.Minute,
)
total := logql.Rate(
    logql.NewLogQuery().Eq("job", "api"),
    5*time.Minute,
)

// Error rate as percentage
expr := logql.Mul(logql.Div(errors, total), &logql.Literal{Value: 100})
fmt.Println(expr.String())
// (rate({job="api"} |= "error" [5m]) / rate({job="api"} [5m])) * 100

// Comparison with bool modifier
alert := logql.CmpGt(
    logql.Rate(logql.NewLogQuery().Eq("job", "api").LineContains("error"), 5*time.Minute),
    &logql.Literal{Value: 10},
).Bool()
fmt.Println(alert.String())
// rate({job="api"} |= "error" [5m]) > bool 10
```

Available operators: `Add`, `Sub`, `Mul`, `Div`, `Mod`, `Pow`, `CmpEq`, `CmpNeq`, `CmpGt`, `CmpGte`, `CmpLt`, `CmpLte`, `And`, `Or`, `Unless`.

### Error Handling

`Build()` returns `(string, error)` and validates:

- At least one stream selector is required
- Label names cannot be empty
- Regex patterns must be valid
- Duration must be positive for range aggregations
- Quantile must be between 0 and 1
- `topk`/`bottomk` k must be > 0

```go
q := logql.NewLogQuery() // no selectors
_, err := q.Build()
// err: "logql: at least one stream selector is required"
```

`String()` calls `Build()` and panics on error — use it only when the query is known to be valid.

---

## Running Loki Locally with Docker

The `examples/` directory contains a complete Docker Compose setup to run Loki and Grafana locally, along with a Go program that demonstrates building LogQL queries and sending them to Loki.

### Setup

```
examples/
├── docker-compose.yml      # Loki + Grafana + log generator
├── loki-config.yml         # Minimal Loki configuration
└── main.go                 # Example Go program using go-logql
```

### 1. Start Loki

```bash
cd examples
docker compose up -d
```

This starts:
- **Loki** on `http://localhost:3100`
- **Grafana** on `http://localhost:3000` (admin/admin)

### 2. Push Some Logs

You can push logs to Loki using its HTTP API. Here's a quick way using curl:

```bash
curl -X POST "http://localhost:3100/loki/api/v1/push" \
  -H "Content-Type: application/json" \
  -d '{
    "streams": [
      {
        "stream": { "job": "api", "env": "prod", "instance": "api-1" },
        "values": [
          ["'"$(date +%s)"'000000000", "{\"level\":\"error\",\"status\":500,\"msg\":\"internal server error\",\"latency_ms\":120}"],
          ["'"$(date +%s)"'000000001", "{\"level\":\"info\",\"status\":200,\"msg\":\"request completed\",\"latency_ms\":15}"],
          ["'"$(date +%s)"'000000002", "{\"level\":\"error\",\"status\":502,\"msg\":\"bad gateway\",\"latency_ms\":5000}"],
          ["'"$(date +%s)"'000000003", "{\"level\":\"warn\",\"status\":429,\"msg\":\"rate limited\",\"latency_ms\":2}"],
          ["'"$(date +%s)"'000000004", "{\"level\":\"info\",\"status\":200,\"msg\":\"health check ok\",\"latency_ms\":1}"]
        ]
      },
      {
        "stream": { "job": "web", "env": "prod", "instance": "web-1" },
        "values": [
          ["'"$(date +%s)"'000000005", "{\"level\":\"info\",\"status\":200,\"msg\":\"page rendered\",\"latency_ms\":45}"],
          ["'"$(date +%s)"'000000006", "{\"level\":\"error\",\"status\":500,\"msg\":\"template error\",\"latency_ms\":200}"]
        ]
      }
    ]
  }'
```

### 3. Run the Example Program

```bash
cd examples
go run main.go
```

The program builds several LogQL queries and executes them against the local Loki instance.

### 4. Explore in Grafana

Open http://localhost:3000, go to **Explore**, select the **Loki** data source, and paste any of the generated queries.

### 5. Cleanup

```bash
cd examples
docker compose down -v
```

---

## API Reference

### Log Query Builder

| Method | Output |
|---|---|
| `NewLogQuery()` | Creates a new empty builder |
| `.Eq(label, value)` | `{label="value"}` |
| `.Neq(label, value)` | `{label!="value"}` |
| `.Re(label, pattern)` | `{label=~"pattern"}` |
| `.Nre(label, pattern)` | `{label!~"pattern"}` |
| `.LineContains(text)` | `\|= "text"` |
| `.LineNotContains(text)` | `!= "text"` |
| `.LineMatch(pattern)` | `\|~ "pattern"` |
| `.LineNotMatch(pattern)` | `!~ "pattern"` |
| `.JSON(labels...)` | `\| json [labels]` |
| `.Logfmt(labels...)` | `\| logfmt [labels]` |
| `.Regexp(pattern)` | `\| regexp "pattern"` |
| `.Pattern(pattern)` | `\| pattern "pattern"` |
| `.Unpack(labels...)` | `\| unpack [labels]` |
| `.LabelEqual(label, value)` | `\| label == "value"` |
| `.LabelNotEqual(label, value)` | `\| label != "value"` |
| `.LabelGreater(label, value)` | `\| label > value` |
| `.LabelGreaterEq(label, value)` | `\| label >= value` |
| `.LabelLess(label, value)` | `\| label < value` |
| `.LabelLessEq(label, value)` | `\| label <= value` |
| `.LabelRe(label, pattern)` | `\| label =~ "pattern"` |
| `.LabelNre(label, pattern)` | `\| label !~ "pattern"` |
| `.LineFormat(template)` | `\| line_format "template"` |
| `.LabelFormatEntry(dst, src)` | `\| label_format dst=src` |
| `.Drop(labels...)` | `\| drop l1, l2` |
| `.Keep(labels...)` | `\| keep l1, l2` |
| `.Decolorize()` | `\| decolorize` |
| `.Unwrap(label)` | `\| unwrap label` |
| `.Build()` | `(string, error)` |
| `.String()` | `string` (panics on error) |

### Metric Query Constructors

`Rate`, `CountOverTime`, `BytesRate`, `BytesOverTime`, `AbsentOverTime`, `FirstOverTime`, `LastOverTime`, `SumOverTime`, `AvgOverTime`, `MaxOverTime`, `MinOverTime`, `StddevOverTime`, `StdvarOverTime`, `QuantileOverTime`

### Metric Query Methods

`Sum`, `Avg`, `Min`, `Max`, `Count`, `Stddev`, `Stdvar`, `TopK`, `BottomK`, `Sort`, `SortDesc`, `By`, `Without`, `Offset`, `Build`, `String`

### Expression Constructors

`Add`, `Sub`, `Mul`, `Div`, `Mod`, `Pow`, `CmpEq`, `CmpNeq`, `CmpGt`, `CmpGte`, `CmpLt`, `CmpLte`, `And`, `Or`, `Unless`

### Expression Methods

`Bool`, `Build`, `String`

## License

MIT
