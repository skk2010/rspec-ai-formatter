# RSpec AI Formatter

AI-friendly RSpec formatter optimized for minimal token usage in LLM contexts.

## Why?

Standard RSpec formatters waste tokens on visual noise:
- **Progress formatter**: Dots and asterisks (`.F*`) with no file context
- **Documentation formatter**: Hierarchical descriptions with indentation whitespace
- **Both**: Failures dumped at end with redundant stack traces

**AI Formatter**: One line per test, structured NDJSON, references to detailed logs.

## Installation

Add to your Gemfile:

```ruby
group :test do
  gem 'rspec-ai-formatter', require: false
end
```

## Usage

### Basic

```bash
# Via CLI helper
rspec-ai

# Via RSpec directly
rspec --format RSpec::AiFormatter::Formatter

# With custom log directory
rspec-ai --ai-logs-dir logs/test -- spec/
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `RSPEC_AI_LOGS` | Directory for failure logs | `tmp/rspec_logs` |
| `RSPEC_AI_CLEAN` | Clean logs before run | `0` |
| `RSPEC_AI_FULL` | Enable full output (default is minimal) | `0` |
| `RSPEC_AI_SIGNATURES` | Enable error signature hashing | `0` |
| `RSPEC_AI_DEDUP` | Deduplicate identical errors | `0` |

### Output Modes

**Minimal mode (default)** — optimized for AI and CI:

```bash
bundle exec rspec --format RSpec::AiFormatter::Formatter
```

Output: `start`, failures, skips, `done`. Passing tests omitted.

```json
{"t":"start","total":100}
{"t":"test","id":"spec/api_spec.rb:10","s":"fail","e":{"type":"Error","msg":"timeout","loc":"spec/api_spec.rb:12"}}
{"t":"test","id":"spec/user_spec.rb:5","s":"skip","skip":"pending"}
{"t":"done","passed":98,"failed":1,"skipped":1,"total":100,"time":1234}
```

**Full mode** — with all details:

```bash
RSPEC_AI_FULL=1 bundle exec rspec --format RSpec::AiFormatter::Formatter
```

Includes: test names, timestamps, timing for every test.

| Mode | Passing tests | Failures | Skips | Events for 1000 tests |
|------|---------------|----------|-------|----------------------|
| Minimal (default) | Omitted | Full | Minimal | ~50 |
| Full | Full event | Full | Full | ~1002 |

**Use full mode when:**
- Debugging individual test performance
- You need to see all test names
- Parsing requires timing data per test
- Human-readable output is priority

**Minimal mode removes:**
- Passing tests (100% savings)
- Test names (`n`) for skips
- Timestamps (`ts`) on individual tests
- Timing (`time`) for skips  
- Timestamp from `done` event
- Line end ranges in `id`
- `./` prefix in file paths

### Combined with Other Formatters

```bash
# AI format to file, progress to console
rspec --format progress --format RSpec::AiFormatter::Formatter --out rspec.jsonl
```

### GitHub Actions

The formatter auto-detects `GITHUB_ACTIONS=true` and emits workflow commands for inline PR annotations:

```yaml
- name: Run tests
  env:
    GITHUB_ACTIONS: true  # Usually already set by GitHub
  run: bundle exec rspec --format RSpec::AiFormatter::Formatter
```

**Annotations appear on:**
- Failed tests → `::error` with file/line
- Skipped/pending tests → `::warning`

**Example output:**
```
::error file=spec/models/user_spec.rb,line=42::expected false, got true
::warning file=spec/api/client_spec.rb,line=15::Skipped: pending implementation
```

To disable annotations but keep NDJSON:
```bash
GITHUB_ACTIONS= bundle exec rspec --format RSpec::AiFormatter::Formatter
```

### Parallel Tests

When using `parallel_tests`, each process writes its own output file. Merge them with `rspec-ai-merge`:

```bash
# Run tests in parallel, each with unique output file
parallel_rspec --format RSpec::AiFormatter::Formatter --out tmp/parallel_{%}.jsonl -- spec/

# Merge outputs
rspec-ai-merge tmp/parallel_*.jsonl > combined.jsonl

# With deduplication across all parallel runs
rspec-ai-merge --dedup tmp/parallel_*.jsonl > combined.jsonl
```

**Merge options:**
```bash
rspec-ai-merge --help

# Sort by timestamp (default)
rspec-ai-merge --output combined.jsonl file1.jsonl file2.jsonl

# Skip sorting, keep file order
rspec-ai-merge --no-sort file1.jsonl file2.jsonl

# Deduplicate errors across files
rspec-ai-merge --dedup file1.jsonl file2.jsonl

# Skip final summary
rspec-ai-merge --no-summary file1.jsonl file2.jsonl
```

**Merged output includes:**
- All test events sorted by timestamp
- Combined `done` event with totals from all files
- Deduplication summaries (if enabled)

## Output Format

### NDJSON Stream

```json
{"t":"start","suite":["spec/models/user_spec.rb"],"total":3,"ts":"2025-06-25T14:30:22.123Z"}
{"t":"test","id":"spec/models/user_spec.rb:15-25","n":"User>valid?>requires email","s":"pass","time":12,"ts":"2025-06-25T14:30:22.135Z"}
{"t":"test","id":"spec/models/user_spec.rb:27-40","n":"User>valid?>rejects invalid format","s":"fail","time":45,"e":{"type":"ExpectationNotMet","msg":"expected false, got true","loc":"spec/models/user_spec.rb:42","log":"tmp/rspec_logs/user_spec_27.log"},"ts":"2025-06-25T14:30:22.180Z"}
{"t":"test","id":"spec/models/user_spec.rb:42-55","n":"User>valid?>accepts valid format","s":"skip","time":0,"skip":"pending implementation","ts":"2025-06-25T14:30:22.181Z"}
{"t":"done","passed":1,"failed":1,"skipped":1,"total":3,"time":1247,"ts":"2025-06-25T14:30:23.370Z"}
```

### Log Files

```
tmp/rspec_logs/
├── user_spec_27.log          # Per-failure details
├── api_client_15.log
└── index.json                # Machine-readable index
```

Example failure log:

```
================================================================================
TEST: User > valid? > rejects invalid format
LOCATION: spec/models/user_spec.rb:27
STATUS: FAIL
TIME: 45ms
================================================================================

ERROR: ExpectationNotMet
MESSAGE:
expected false, got true

EXPECTED:
false

ACTUAL:
true

BACKTRACE:
spec/models/user_spec.rb:42:in `block (3 levels) in <top (required)>'
...
```

## Schema

### Event Types

| `t` | Description | Additional Fields |
|-----|-------------|-------------------|
| `start` | Suite started | `suite`, `total` |
| `test` | Test completed | `id`, `n`, `s`, `time`, `e`/`skip` |
| `done` | Suite finished | `passed`, `failed`, `skipped`, `total`, `time` |

### Status Values

| `s` | Meaning |
|-----|---------|
| `pass` | Test passed |
| `fail` | Test failed (see `e` for details) |
| `skip` | Test skipped/pending (see `skip` for reason) |

### Error Object (`e`)

| Field | Description |
|-------|-------------|
| `type` | Error class (shortened) |
| `msg` | Truncated message (200 chars) |
| `loc` | File:line of failure |
| `log` | Path to full log file |
| `sig` | MD5 signature of error (if dedup/signatures enabled) |
| `diff` | Expected/actual diff (for expectations) |

### Deduplication

When `RSPEC_AI_DEDUP=1`, identical errors are collapsed:

```json
// First occurrence - full details
{"t":"test","id":"spec/api_spec.rb:20","n":"GET /users returns 200","s":"fail","e":{"type":"TimeoutError","msg":"execution expired","loc":"spec/api_spec.rb:25","sig":"a3f9e2d1"}}

// Duplicates - lightweight reference
{"t":"dedup","sig":"a3f9e2d1","id":"spec/api_spec.rb:40","n":"GET /users with params","first":"spec/api_spec.rb:20"}
{"t":"dedup","sig":"a3f9e2d1","id":"spec/api_spec.rb:60","n":"POST /users creates user","first":"spec/api_spec.rb:20"}

// Summary at end
{"t":"dedup_summary","sig":"a3f9e2d1","type":"TimeoutError","msg":"execution expired","count":3,"first":"spec/api_spec.rb:20","examples":["spec/api_spec.rb:20","spec/api_spec.rb:40","spec/api_spec.rb:60"]}
```

Useful when a shared setup/teardown failure cascades through many tests.

## Token Efficiency

| Scenario | Progress | Documentation | AI Formatter |
|----------|----------|---------------|--------------|
| 100 tests, all pass | ~200 | ~800 | ~150 |
| 10 failures with traces | ~2000 | ~2500 | ~300 + files |
| Parsing complexity | Hard | Hard | Trivial |

## Features

- ✅ **Streaming NDJSON**: Real-time output, parse-as-you-go
- ✅ **Minimal mode**: Ultra-compact output for massive test suites (80% smaller)
- ✅ **Location tracking**: File + line start-end for each test
- ✅ **Failure isolation**: Full output to separate log files
- ✅ **Error signatures**: Group similar failures by hash
- ✅ **Error deduplication**: Collapse identical errors, show "and 4 more like this"
- ✅ **Parallel test merging**: Merge outputs from parallel_tests runs
- ✅ **Diff generation**: Smart expected/actual comparison
- ✅ **Truncation**: Prevent token explosion on large outputs
- ✅ **ANSI-free**: Clean text, no escape codes
- ✅ **GitHub Actions**: Auto-detects and emits `::error`/`::warning` annotations

## TODO

### CI/CD Integration
- [x] GitHub Actions workflow command integration — Auto-detect `GITHUB_ACTIONS` env and emit `::error` / `::warning` commands for inline PR annotations

### Error Intelligence
- [x] Error pattern deduplication across test runs — Group failures by signature hash, show "and 4 more like this"
- [ ] Quick-fix hints integration with `did_you_mean` — Suggest typo corrections, similar method names
- [ ] Error context snippets — Include 3-5 lines of source code around failure in log files

### Performance & Insights
- [ ] Performance baseline tracking — Compare to previous run, flag regressions >50%
- [ ] Test selection metadata — Add tags, flakiness score, last failure date to each test event
- [ ] Slowest tests report — Top N slowest tests in summary

### Compatibility & Tooling
- [ ] JUnit XML compatibility mode — Dual output for systems requiring XML
- [x] Parallel test log merging — Clean merge of outputs from `parallel_tests` runs
- [ ] Screenshot capture for system tests — Auto-capture Capybara screenshot path on failure
- [ ] Custom output templates — User-defined NDJSON schema / field selection

## License

MIT
