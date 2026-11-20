#!/bin/sh
. "$(dirname "$0")/lib.sh"
U="$REPO/helpmekaito/scripts/kaito-usage.mjs"

# A home with no runner logs, no keys, and a small price list with round numbers.
mk_usage() {
  mk_home
  unset CLAUDE_CONFIG_DIR GEMINI_CLI_HOME XDG_DATA_HOME KAITO_MODELS_MODULE KAITO_USAGE_SQLITE GOOGLE_GENAI_USE_VERTEXAI
  unset ANTHROPIC_API_KEY OPENAI_API_KEY CODEX_API_KEY GEMINI_API_KEY GOOGLE_API_KEY XAI_API_KEY OPENROUTER_API_KEY
  USERPROFILE=$HOME; export USERPROFILE   # Windows: the real profile is never read
  D=$(day 0); KAITO_TODAY=$D; export KAITO_TODAY
  KAITO_PRICES="$HOME/prices.json"; export KAITO_PRICES
  cat > "$KAITO_PRICES" <<'EOF'
{ "updated": "2026-01-02", "currency": "USD", "unit": "per 1M tokens", "models": [
  { "match": "claude-opus-5.5", "input": 1, "output": 2, "cache_read": 0.5, "cache_write": 4, "cache_write_1h": 8 },
  { "match": "claude-opus-5", "input": 100, "output": 100, "cache_read": 100, "cache_write": 100 },
  { "match": "claude-haiku-9", "input": 1, "output": 1, "cache_read": 1, "cache_write": 4, "cache_write_1h": null },
  { "match": "gpt-6.2-sol", "input": 2, "output": 10, "cache_read": 0.1, "cache_write": null },
  { "match": "gpt-5", "input": 3, "output": 3, "cache_read": null, "cache_write": null },
  { "match": "chat-latest", "input": 50, "output": 50, "cache_read": 50, "cache_write": null },
  { "match": "gemini-4-argon", "input": 1, "output": 1, "cache_read": 1, "cache_write": null }
] }
EOF
}
# day N: the calendar day N days before today (local), by date arithmetic like the script's.
day() { node -e 'const n=new Date();console.log(new Date(Date.UTC(n.getFullYear(),n.getMonth(),n.getDate()-process.argv[1],12)).toISOString().slice(0,10))' "$1"; }
report() { node "$U" report "$@" > "$HOME/out" 2>&1 || { cat "$HOME/out"; exit 1; }; }
# row <day> <model>: that table row with single spaces.
row() { grep "^$1  *$2 " "$HOME/out" | tr -s ' '; }
has() { grep -qF -- "$1" "$HOME/out" || { echo "  missing: $1"; cat "$HOME/out"; exit 1; }; }
hasnt() { ! grep -qF -- "$1" "$HOME/out" || { echo "  should not print: $1"; cat "$HOME/out"; exit 1; }; }
# claude_line <msg id> <request id> <model> <day> <input> <output> <cache read> <cache write> <of which 1h>
# The model is written as given, so pass it with its JSON quotes when it is not a plain word.
claude_line() {
  case "$3" in [0-9]*|\"*) m=$3 ;; *) m="\"$3\"" ;; esac
  echo "{\"type\":\"assistant\",\"requestId\":\"$2\",\"timestamp\":\"$4T12:00:00\",\"message\":{\"id\":\"$1\",\"model\":$m,\"usage\":{\"input_tokens\":$5,\"output_tokens\":$6,\"cache_read_input_tokens\":$7,\"cache_creation_input_tokens\":$8,\"cache_creation\":{\"ephemeral_1h_input_tokens\":$9}}}}"
}

test_usage_claude_parse_dedupe_and_price() {
  mk_usage
  p="$HOME/.claude/projects/proj"; mkdir -p "$p/sess/subagents"
  {
    echo '{"type":"user","timestamp":"'"$D"'T12:00:00","message":{"role":"user","content":"hi"}}'
    claude_line m1 r1 claude-opus-5-5 "$D" 10 5 0 0 0           # streamed twice: the partial line loses
    claude_line m1 r1 claude-opus-5-5 "$D" 600000 500000 2000000 1000000 250000
    claude_line m9 r9 '<synthetic>' "$D" 0 0 0 0 0
    echo 'not json "usage"'
    echo 'null'
    echo '{"message":{"usage":7,"model":"x"},"note":"usage"}'
  } > "$p/sess.jsonl"
  claude_line m2 r2 claude-opus-5-5 "$D" 400000 0 0 0 0 > "$p/sess/subagents/agent-1.jsonl"
  claude_line m1 r1 claude-opus-5-5 "$D" 600000 500000 2000000 1000000 250000 > "$p/resumed.jsonl"  # history copied into a resumed session
  claude_line m1 r1 claude-opus-5-5 "$D" 10 5 0 0 0 > "$p/zz-read-last.jsonl"   # a partial copy in the last file read must not win
  report
  # 1M in $1 + 0.5M out $1 + 2M cache read $1 + 0.75M 5m write $3 + 0.25M 1h write $2
  assert_eq "$(row "$D" claude-opus-5-5)" "$D claude-opus-5-5 1,000,000 500,000 2,000,000 1,000,000 \$8.00" row
  has 'claude: read, 2 model responses'
  hasnt synthetic
  hasnt 'could not be read'
  has 'Prices are estimates'
  has 'est. price'
}

test_usage_bad_records_do_not_stop_the_report() {
  mk_usage
  p="$HOME/.claude/projects/p"; mkdir -p "$p"
  { claude_line a ra 7 "$D" 1000 0 0 0 0; claude_line b rb claude-opus-5-5 "$D" 1000000 0 0 0 0; } > "$p/s.jsonl"
  GEMINI_CLI_HOME="$HOME/g"; export GEMINI_CLI_HOME
  c="$GEMINI_CLI_HOME/.gemini/tmp/proj/chats"; mkdir -p "$c"
  echo '{"sessionId":"a","messages":{}}' > "$c/session-a.json"       # a messages value that is not a list
  echo '{"sessionId":"b","messages":[' > "$c/session-b.json"         # cut-off JSON
  echo '{"id":"g1","timestamp":"'"$D"'T12:00:00","type":"gemini","model":"gemini-4-argon","tokens":{"input":2000000,"output":0,"cached":0}}' > "$c/session-c.jsonl"
  report
  assert_eq "$(row "$D" 7)" "$D 7 1,000 0 0 0 no price" number_model_is_shown_not_fatal
  assert_eq "$(row "$D" claude-opus-5-5 | sed 's/.* //')" '$1.00' claude_row_after_bad_one
  assert_eq "$(row "$D" gemini-4-argon | sed 's/.* //')" '$2.00' sibling_file_still_read
  has 'gemini: read, 1 model responses in the window; 1 log file could not be read and is not counted'
}

test_usage_claude_config_dir_and_days() {
  mk_usage
  CLAUDE_CONFIG_DIR="$HOME/cc"; export CLAUDE_CONFIG_DIR
  mkdir -p "$CLAUDE_CONFIG_DIR/projects/p" "$HOME/.claude/projects/p"
  old=$(day 10)
  { claude_line a ra claude-opus-5-5 "$D" 1000000 0 0 0 0; claude_line b rb claude-opus-5-5 "$old" 2000000 0 0 0 0; } > "$CLAUDE_CONFIG_DIR/projects/p/s.jsonl"
  claude_line c rc claude-opus-5-5 "$D" 7 0 0 0 0 > "$HOME/.claude/projects/p/s.jsonl"   # not the configured dir
  report
  has "last 7 days ($(day 6) to $D)"
  assert_eq "$(row "$D" claude-opus-5-5)" "$D claude-opus-5-5 1,000,000 0 0 0 \$1.00" today
  hasnt "$old"
  report 30
  assert_eq "$(row "$old" claude-opus-5-5)" "$old claude-opus-5-5 2,000,000 0 0 0 \$2.00" older
  assert_eq "$(grep '^total' "$HOME/out" | tr -s ' ')" "total 3,000,000 0 0 0 \$3.00" total
  node "$U" report nope > /dev/null 2>&1 && exit 1
  node "$U" report 0 > /dev/null 2>&1 && exit 1
  return 0
}

test_usage_window_is_counted_in_calendar_days() {
  mk_usage
  # Across a 23-hour day (US clocks go forward on 2026-03-08) and in zones far from UTC.
  for tz in America/New_York Pacific/Apia Pacific/Chatham UTC; do
    TZ=$tz KAITO_TODAY=2026-03-09 report 2;   has '(2026-03-08 to 2026-03-09)'
    TZ=$tz KAITO_TODAY=2026-03-09 report 400; has '(2025-02-03 to 2026-03-09)'
    TZ=$tz KAITO_TODAY=2026-11-02 report 3;   has '(2026-10-31 to 2026-11-02)'
  done
}

# tc <input> <cached> <output> [time] [turn input] [turn cached] [turn output]: a Codex token_count line with these session totals.
tc() { echo "{\"timestamp\":\"${D}T${4:-12:00:00}\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":$1,\"cached_input_tokens\":$2,\"cache_write_input_tokens\":0,\"output_tokens\":$3,\"reasoning_output_tokens\":7,\"total_tokens\":$(($1 + $3))},\"last_token_usage\":{\"input_tokens\":${5:-999},\"cached_input_tokens\":${6:-0},\"cache_write_input_tokens\":0,\"output_tokens\":${7:-0},\"total_tokens\":${5:-999}}}}}"; }
ctx() { echo "{\"timestamp\":\"${D}T12:00:00\",\"type\":\"turn_context\",\"payload\":{\"model\":\"$1\"}}"; }

test_usage_codex_cumulative_not_double_counted() {
  mk_usage
  CODEX_HOME="$HOME/cx"; export CODEX_HOME
  s="$CODEX_HOME/sessions/2026/01/01"; mkdir -p "$s"
  {
    echo '{"timestamp":"'"$D"'T12:00:00","type":"session_meta","payload":{"id":"s1"}}'
    ctx gpt-6.2-sol
    echo '{"timestamp":"'"$D"'T12:00:00","type":"event_msg","payload":{"type":"token_count","info":null}}'
    tc 1000000 400000 100000 12:00:01 1000000 400000 100000
    tc 1000000 400000 100000 12:00:02          # the same total logged again adds nothing
    tc 3000000 1400000 300000 12:00:03
    ctx mystery-1
    tc 3500000 1400000 300000 12:00:04         # 500,000 new input on a model with no price
  } > "$s/rollout-a.jsonl"
  { ctx gpt-6.2-sol; tc 400000 0 0 12:00:05 400000; } > "$s/rollout-b.jsonl"   # a second session starts from zero
  report
  # input excludes cached: (3.0M - 1.4M) + 0.4M = 2.0M at $2, 0.3M out at $10, 1.4M cached at $0.10.
  assert_eq "$(row "$D" gpt-6.2-sol)" "$D gpt-6.2-sol 2,000,000 300,000 1,400,000 0 \$7.14" priced
  assert_eq "$(row "$D" mystery-1)" "$D mystery-1 500,000 0 0 0 no price" unknown_model
  has 'No price for mystery-1 (500,000 tokens)'
  has 'left out of the total'
  grep '^total' "$HOME/out" | grep -q '(priced models)' || exit 1
  hasnt '3,500,000'
}

test_usage_codex_fork_copy_and_archive() {
  mk_usage
  CODEX_HOME="$HOME/cx"; export CODEX_HOME
  s="$CODEX_HOME/sessions/2026/01/01"; mkdir -p "$s" "$CODEX_HOME/archived_sessions"
  { ctx gpt-6.2-sol; tc 1000000 0 0 12:00:01 1000000; tc 2000000 0 0 12:00:02 1000000; } > "$s/rollout-1-parent.jsonl"
  # A fork carries the parent's total forward: only its own turn (500,000) is new.
  { echo '{"type":"session_meta","payload":{"id":"f","forked_from_id":"p"}}'; ctx gpt-6.2-sol; tc 2500000 0 0 12:00:03 500000; tc 2700000 0 0 12:00:04 200000; } > "$s/rollout-2-fork.jsonl"
  # A resumed session copies the parent's counts line for line, then adds 300,000.
  { ctx gpt-6.2-sol; tc 1000000 0 0 12:00:01 1000000; tc 2000000 0 0 12:00:02 1000000; tc 2300000 0 0 12:00:05 300000; } > "$s/rollout-3-resumed.jsonl"
  { ctx gpt-6.2-sol; tc 4000000 0 0 12:00:06 4000000; } > "$CODEX_HOME/archived_sessions/rollout-0-archived.jsonl"
  report
  # 2.0M parent + 0.7M fork + 0.3M resumed + 4.0M archived
  assert_eq "$(row "$D" gpt-6.2-sol)" "$D gpt-6.2-sol 7,000,000 0 0 0 \$14.00" row
  rm -r "$CODEX_HOME/sessions"
  report
  assert_eq "$(row "$D" gpt-6.2-sol)" "$D gpt-6.2-sol 4,000,000 0 0 0 \$8.00" archive_alone_is_read
}

test_usage_gemini_fixture() {
  mk_usage
  GEMINI_CLI_HOME="$HOME/g"; export GEMINI_CLI_HOME
  c="$GEMINI_CLI_HOME/.gemini/tmp/proj/chats"; mkdir -p "$c"
  cat > "$c/session-2026-01-01T10-00-abcd1234.jsonl" <<EOF
{"sessionId":"abcd1234","projectHash":"h","startTime":"${D}T12:00:00","kind":"main","messages":[{"id":"g4","timestamp":"${D}T12:00:00","type":"gemini","model":"gemini-4-argon","tokens":{"input":100000,"output":0,"cached":0}}]}
{"id":"u1","timestamp":"${D}T12:00:00","type":"user","content":"hi"}
{"id":"g1","timestamp":"${D}T12:00:00","type":"gemini","model":"gemini-4-argon","content":"","tokens":{"input":5,"output":5,"cached":0,"total":10}}
{"id":"g1","timestamp":"${D}T12:00:00","type":"gemini","model":"gemini-4-argon","content":"x","tokens":{"input":1000000,"output":200000,"cached":400000,"thoughts":50000,"tool":10000,"total":1260000}}
{"\$set":{"lastUpdated":"${D}T12:00:01"}}
{"\$set":{"messages":[{"id":"g1","timestamp":"${D}T12:00:00","type":"gemini","model":"gemini-4-argon","tokens":{"input":1000000,"output":200000,"cached":400000,"thoughts":50000,"tool":10000}},{"id":"g5","timestamp":"${D}T12:00:00","type":"gemini","model":"gemini-4-argon","tokens":{"input":0,"output":50000,"cached":0}}]}}
{"id":"g3","timestamp":"${D}T12:00:00","type":"gemini","model":"gemini-4-argon","content":"x","tokens":null}
EOF
  cat > "$c/session-2026-01-01T09-00-old00000.json" <<EOF
{"sessionId":"old","messages":[{"id":"g2","timestamp":"${D}T12:00:00","type":"gemini","model":"gemini-4-argon","tokens":{"input":290000,"output":0,"cached":0,"total":290000}}]}
EOF
  # Not a chat file: it is inside the window and well formed, so it would show up if it were scanned.
  echo '{"id":"x","timestamp":"'"$D"'T12:00:00","type":"gemini","model":"gemini-4-argon","tokens":{"input":9000000,"output":0,"cached":0}}' > "$GEMINI_CLI_HOME/.gemini/tmp/proj/logs.jsonl"
  report
  # g1 once: input 1.0M - 0.4M cached + 10k tool = 610k, output 200k + 50k thoughts; g2 290k and g4 100k input
  # (legacy file, metadata line); g5 50k output (checkpoint)
  assert_eq "$(row "$D" gemini-4-argon)" "$D gemini-4-argon 1,000,000 300,000 400,000 0 \$1.70" row
  has 'gemini: read, 4 model responses'
}

test_usage_gemini_under_userprofile() {
  mk_usage
  USERPROFILE="$HOME/winhome"; export USERPROFILE
  c="$USERPROFILE/.gemini/tmp/proj/chats"; mkdir -p "$c"
  echo '{"id":"g1","timestamp":"'"$D"'T12:00:00","type":"gemini","model":"gemini-4-argon","tokens":{"input":3000000,"output":0,"cached":0}}' > "$c/session-a.jsonl"
  report
  assert_eq "$(row "$D" gemini-4-argon | sed 's/.* //')" '$3.00' found
}

# mk_db <sql file>: makes the opencode database with the sqlite3 command or node:sqlite. Fails when this machine has neither.
mk_db() {
  mkdir -p "$HOME/.local/share/opencode"
  db="$HOME/.local/share/opencode/opencode.db"; rm -f "$db"
  if command -v sqlite3 > /dev/null 2>&1; then sqlite3 "$db" < "$1"; return; fi
  cat > "$HOME/mkdb.mjs" <<'EOF'
import { readFileSync } from 'node:fs';
process.emitWarning = () => {};
const { DatabaseSync } = await import('node:sqlite');
const db = new DatabaseSync(process.argv[2]);
for (const sql of readFileSync(process.argv[3], 'utf8').split('\n').filter(Boolean)) db.prepare(sql).run();
db.close();
EOF
  node "$HOME/mkdb.mjs" "$db" "$1" 2> /dev/null
}
no_sqlite() {
  echo "skip: no node:sqlite and no sqlite3 here, so the reader cannot be fed a database"
  mkdir -p "$HOME/.local/share/opencode"; : > "$HOME/.local/share/opencode/opencode.db"
  report
  has 'opencode: not readable, '
}
ms() { node -e 'console.log(new Date(process.argv[1]+"T12:00:00").getTime()+Number(process.argv[2]||0))' "$D" "$1"; }

test_usage_opencode_db_or_named() {
  mk_usage
  now=$(ms); later=$(ms 60000)
  a='{"time":{"created":'$now'},"model":{"id":"gpt-6.2-sol","providerID":"openai"},"tokens":{"input":1000000,"output":90000,"reasoning":10000,"cache":{"read":1000000,"write":0}}}'
  cat > "$HOME/oc.sql" <<EOF
create table session_message(id text, session_id text, type text, seq integer, time_created integer, data text);
insert into session_message values('a','s','assistant',1,$now,'$a');
insert into session_message values('a2','fork','assistant',1,$later,'$a');
insert into session_message values('b','s','assistant',2,$now,'{"model":{"id":"opus","providerID":"x"},"tokens":{"input":5,"output":5,"reasoning":0,"cache":{"read":0,"write":10}}}');
insert into session_message values('c','s','user',3,$now,'{"text":"tokens"}');
insert into session_message values('d','s','assistant',4,1000,'{"model":{"id":"gpt-6.2-sol"},"tokens":{"input":555,"output":0,"reasoning":0,"cache":{"read":0,"write":0}}}');
insert into session_message values('e','s','compaction',5,$now,'{"status":"completed","model":{"id":"gpt-6.2-sol"},"tokens":{"input":500000,"output":0,"reasoning":0,"cache":{"read":0,"write":0}}}');
EOF
  mk_db "$HOME/oc.sql" || { no_sqlite; return 0; }
  report
  # $2 input + $1 output (90k + 10k reasoning at $10) + $0.10 cache read, once: the forked copy (a2) is the
  # same response. The compaction adds 0.5M input ($1). The user row and the old row are out.
  assert_eq "$(row "$D" gpt-6.2-sol)" "$D gpt-6.2-sol 1,500,000 100,000 1,000,000 0 \$4.10" row
  assert_eq "$(row "$D" opus)" "$D opus 5 5 0 10 no price" alias_has_no_price
  has 'opencode: read, 3 model responses'
  if command -v sqlite3 > /dev/null 2>&1; then   # the sqlite3 command gives the same answer
    KAITO_USAGE_SQLITE=cli report
    assert_eq "$(row "$D" gpt-6.2-sol)" "$D gpt-6.2-sol 1,500,000 100,000 1,000,000 0 \$4.10" cli_row
    has 'opencode: read, 3 model responses'
  fi
}

test_usage_opencode_v1_table_and_unknown_layout() {
  mk_usage
  now=$(ms)
  cat > "$HOME/v1.sql" <<EOF
create table message(id text, session_id text, time_created integer, time_updated integer, data text);
insert into message values('a','s',$now,$now,'{"role":"assistant","modelID":"gpt-5","providerID":"openai","tokens":{"input":1000000,"output":0,"reasoning":0,"cache":{"read":0,"write":0}}}');
insert into message values('b','s',$now,$now,'{"role":"user","tokens":{"input":777}}');
EOF
  mk_db "$HOME/v1.sql" || { no_sqlite; return 0; }
  report
  assert_eq "$(row "$D" gpt-5)" "$D gpt-5 1,000,000 0 0 0 \$3.00" v1_row
  has 'opencode: read, 1 model responses'
  echo 'create table something_else(id text);' > "$HOME/other.sql"
  mk_db "$HOME/other.sql" || exit 1
  report
  has 'opencode: not readable, unknown database layout'
}

test_usage_sqlite3_command_reads_no_init_file_and_big_output() {
  skip_on_win "node cannot start a shell-script sqlite3 stub there" && return 0
  mk_usage
  mkdir -p "$HOME/.local/share/opencode" "$HOME/bin"; : > "$HOME/.local/share/opencode/opencode.db"
  now=$(ms)
  cat > "$HOME/bin/sqlite3" <<EOF
#!/bin/sh
echo "\$*" >> "$HOME/sqlite-args"
[ -f "\$3" ] && [ ! -s "\$3" ] && echo init-empty >> "$HOME/sqlite-args"
case "\$*" in
  *sqlite_master*) echo session_message ;;
  *) head -c 3000000 /dev/zero | tr '\\0' x; echo; printf '$now\\tgpt-5\\t1000000\\t0\\t0\\t0\\t0\\n' ;;
esac
EOF
  chmod +x "$HOME/bin/sqlite3"
  PATH="$HOME/bin:$PATH" KAITO_USAGE_SQLITE=cli report
  assert_eq "$(row "$D" gpt-5)" "$D gpt-5 1,000,000 0 0 0 \$3.00" three_megabytes_of_output_read
  # every call names an empty init file, so ~/.sqliterc is never run
  assert_eq "$(grep -c '^-batch -init ' "$HOME/sqlite-args")" 2 init_given
  assert_eq "$(grep -c '^init-empty$' "$HOME/sqlite-args")" 2 init_is_an_empty_file
  PATH="$HOME/bin:$PATH" KAITO_USAGE_SQLITE=cli report   # and a failing sqlite3 is not called "no sqlite3"
  printf '#!/bin/sh\necho "Error: file is not a database" >&2\nexit 1\n' > "$HOME/bin/sqlite3"
  PATH="$HOME/bin:$PATH" KAITO_USAGE_SQLITE=cli report
  has 'opencode: not readable, sqlite3 could not read '
  has 'file is not a database'
}

test_usage_unreadable_runners_are_named() {
  mk_usage
  report
  has "claude: not readable, no session logs at "
  has "codex: not readable, no session logs at "
  has "opencode: not readable, no database at "
  has "gemini: not readable, no session logs at "
  has "cursor-agent: not readable, Cursor keeps no token counts on disk"
  has 'No usage found in this window.'
  mkdir -p "$HOME/.local/share/opencode"
  echo 'this is not a database' > "$HOME/.local/share/opencode/opencode.db"
  report
  grep -q '^  opencode: not readable, ..*' "$HOME/out" || { cat "$HOME/out"; exit 1; }
}

test_usage_price_rows_match_families_first_wins() {
  mk_usage
  p="$HOME/.claude/projects/p"; mkdir -p "$p"
  {
    claude_line a ra claude-opus-5-5-20260101 "$D" 1000000 0 0 0 0   # dated id finds its family
    claude_line b rb claude-opus-5-7 "$D" 1000000 0 0 0 0            # a later minor falls back to claude-opus-5
    claude_line c rc gpt-5-mini "$D" 1000000 0 0 0 0                 # a different model, not gpt-5
    claude_line d rd openai/gpt-5-high "$D" 1000000 0 1000000 0 0    # provider prefix and effort suffix; null cache price = input price
    claude_line e re claude-3-opus-20240229 "$D" 1000000 0 0 0 0
    claude_line f rf gpt-5-chat-latest "$D" 1000000 0 0 0 0          # neither gpt-5 nor chat-latest
    claude_line g rg chat-latest "$D" 1000000 0 0 0 0
    claude_line h rh us.anthropic.claude-opus-5-5-v1:0 "$D" 1000000 0 0 0 0   # region and vendor labels in front
    claude_line i ri claude-haiku-9 "$D" 0 0 0 1000000 1000000       # 1h write price is null: input price, not the 5m one
  } > "$p/s.jsonl"
  report
  assert_eq "$(row "$D" claude-opus-5-5-20260101 | sed 's/.* //')" '$1.00' specific_first
  assert_eq "$(row "$D" claude-opus-5-7 | sed 's/.* //')" '$100.00' family_fallback
  assert_eq "$(row "$D" gpt-5-mini | sed 's/.* //')" 'price' sibling_not_matched
  assert_eq "$(row "$D" openai/gpt-5-high | sed 's/.* //')" '$6.00' null_cache_at_input_price
  assert_eq "$(row "$D" claude-3-opus-20240229 | sed 's/.* //')" 'price' old_family_not_matched
  assert_eq "$(row "$D" gpt-5-chat-latest | sed 's/.* //')" 'price' family_inside_another_id_not_matched
  assert_eq "$(row "$D" chat-latest | sed 's/.* //')" '$50.00' exact_id
  assert_eq "$(row "$D" us.anthropic.claude-opus-5-5-v1:0 | sed 's/.* //')" '$1.00' vendor_labels
  assert_eq "$(row "$D" claude-haiku-9 | sed 's/.* //')" '$1.00' null_1h_write_at_input_price
}

# price_list_ok <file>: the checks the shipped list must pass.
price_list_ok() {
  node -e '
    const p = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const bad = (m) => { console.log("  bad price list: " + m); process.exit(1); };
    if (!/^\d{4}-\d\d-\d\d$/.test(p.updated) || p.currency !== "USD" || p.unit !== "per 1M tokens") bad("header");
    const seen = new Set(), num = (v) => typeof v === "number" && v > 0;
    for (const m of p.models) {
      if (typeof m.match !== "string" || !m.match || seen.has(m.match)) bad("match " + m.match);
      seen.add(m.match);
      if (!/^https:\/\//.test(m.source) || !m.vendor) bad("source or vendor of " + m.match);
      for (const k of ["input", "output"]) if (!num(m[k])) bad(k + " of " + m.match);
      for (const k of ["cache_read", "cache_write"]) if (m[k] !== null && !num(m[k])) bad(k + " of " + m.match);
      if (m.cache_write_1h !== undefined && m.cache_write_1h !== null && !num(m.cache_write_1h)) bad("cache_write_1h of " + m.match);
    }
    for (const v of ["anthropic", "openai", "google", "xai"]) if (!p.models.some((m) => m.vendor === v)) bad("no rows for " + v);
  ' "$1"
}

test_usage_real_price_list_is_well_formed() {
  price_list_ok "$REPO/helpmekaito/references/prices.json" || exit 1
  mk_usage
  # the check itself refuses a price that is a string, and the script ignores such a row instead of printing $NaN
  for bad in '"input":"3"' '"input":3,"cache_read":"0.1"' '"input":3,"cache_write_1h":"8"'; do
    echo '{"updated":"2026-01-02","currency":"USD","unit":"per 1M tokens","models":[{"match":"claude-opus-5.5","vendor":"anthropic","source":"https://x","output":2,"cache_read":null,"cache_write":null,'"$bad"'},{"match":"gpt-5","vendor":"openai","source":"https://x","input":3,"output":3,"cache_read":null,"cache_write":null},{"match":"g","vendor":"google","source":"https://x","input":1,"output":1,"cache_read":null,"cache_write":null},{"match":"x","vendor":"xai","source":"https://x","input":1,"output":1,"cache_read":null,"cache_write":null}]}' > "$KAITO_PRICES"
    price_list_ok "$KAITO_PRICES" > /dev/null && { echo "  accepted $bad"; exit 1; }
  done
  mkdir -p "$HOME/.claude/projects/p"
  claude_line a ra claude-opus-5-5 "$D" 1000000 0 0 1000000 1000000 > "$HOME/.claude/projects/p/s.jsonl"
  report
  hasnt NaN
  assert_eq "$(row "$D" claude-opus-5-5 | sed 's/.* //')" 'price' bad_row_prices_nothing
  has 'prices.json has 1 row with a missing or non-number price; it is ignored.'
  unset KAITO_PRICES   # the shipped list prices a current id and never guesses an unknown one
  { claude_line a ra claude-haiku-4-5-20251001 "$D" 1000000 0 0 0 0; claude_line b rb some-new-model-9 "$D" 5 0 0 0 0; claude_line c rc gpt-5-chat-latest "$D" 5 0 0 0 0; } > "$HOME/.claude/projects/p/s.jsonl"
  report
  row "$D" claude-haiku-4-5-20251001 | grep -q ' \$[0-9.]*$' || { cat "$HOME/out"; exit 1; }
  assert_eq "$(row "$D" some-new-model-9 | sed 's/.* //')" 'price' never_a_guess
  assert_eq "$(row "$D" gpt-5-chat-latest | sed 's/.* //')" 'price' not_the_chat_latest_row
}

tier_fixture() {
  mkdir -p "$HOME/.claude/projects/p"
  {
    claude_line a ra big-model "$D" 6000 0 0 0 0
    claude_line b rb small-model "$D" 3000 0 0 0 0
    claude_line c rc mid-model "$D" 500 0 0 0 0
    claude_line d rd odd-model "$D" 500 0 0 0 0
  } > "$HOME/.claude/projects/p/s.jsonl"
}

test_usage_tier_split_with_fixture_module() {
  mk_usage; tier_fixture
  KAITO_MODELS_MODULE="$HOME/models.mjs"; export KAITO_MODELS_MODULE
  echo 'export const tierOf = (m) => ({ "big-model": "hard", "small-model": "light", "mid-model": "standard" })[m] ?? null;' > "$KAITO_MODELS_MODULE"
  report
  has 'Main model: big-model (the model with the most tokens in the window, cache included). Its tier is hard.'
  has 'Cheaper tiers: 3,500 of 10,000 tokens (35%) went to a cheaper tier than the main model (light 3,000, standard 500). 500 tokens are on models with no known tier.'
}

test_usage_tier_split_unavailable_without_module() {
  mk_usage; tier_fixture
  KAITO_MODELS_MODULE="$HOME/absent.mjs"; export KAITO_MODELS_MODULE
  report
  has 'Main model: big-model'
  has 'Cheaper tiers: tier split unavailable'
  has 'est. price'   # the rest of the report still prints
}

test_usage_tier_split_with_real_module() {
  [ -f "$REPO/helpmekaito/scripts/kaito-models.mjs" ] || { echo "skip: helpmekaito/scripts/kaito-models.mjs is not on this branch"; return 0; }
  mk_usage
  mkdir -p "$HOME/.claude/projects/p"
  { claude_line a ra claude-fable-5-2 "$D" 6000 0 0 0 0; claude_line b rb claude-haiku-5-5 "$D" 4000 0 0 0 0; } > "$HOME/.claude/projects/p/s.jsonl"
  report
  has 'Cheaper tiers: 4,000 of 10,000 tokens (40%)'
}

check() { node "$U" consent check "$@"; }

test_usage_consent_ask_yes_ok_then_next_day() {
  mk_usage
  KAITO_TODAY=2026-03-01
  assert_eq "$(check openrouter deepseek/deepseek-v4)" ask first
  assert_no "$KAITO_HOME/usage-consent.json"   # asking records nothing
  node "$U" consent yes deepseek/deepseek-v4 > /dev/null || exit 1
  assert_file "$KAITO_HOME/usage-consent.json"
  assert_eq "$(check openrouter deepseek/deepseek-v4)" ok same_day
  assert_eq "$(check api deepseek/deepseek-v4)" ok same_model_same_day
  assert_eq "$(check openrouter other/model)" ask other_model
  KAITO_TODAY=2026-03-02
  assert_eq "$(check openrouter deepseek/deepseek-v4)" ask next_day
  node "$U" consent yes other/model > /dev/null || exit 1
  assert_eq "$(grep -c 2026-03-01 "$KAITO_HOME/usage-consent.json")" 0 old_yes_dropped
  node "$U" consent check openrouter > /dev/null 2>&1 && exit 1
  node "$U" consent yes > /dev/null 2>&1 && exit 1
  return 0
}

test_usage_consent_subscription_never_asks() {
  mk_usage
  for r in claude codex gemini cursor-agent host; do assert_eq "$(check $r some-model)" ok "$r logged in"; done
  assert_eq "$(check opencode anthropic/claude-opus-5-5)" ok opencode_login
  mkdir -p "$HOME/.codex" "$HOME/.gemini"
  echo '{"auth_mode":"chatgpt","OPENAI_API_KEY":null,"tokens":{"id_token":"t"}}' > "$HOME/.codex/auth.json"
  echo '{"security":{"auth":{"selectedType":"oauth-personal"}}}' > "$HOME/.gemini/settings.json"
  assert_eq "$(check codex gpt-6.2-sol)" ok codex_chatgpt_login
  assert_eq "$(check gemini gemini-4-argon)" ok gemini_google_login
  echo '{"OPENAI_API_KEY":null,"tokens":{"id_token":"t"}}' > "$HOME/.codex/auth.json"
  assert_eq "$(check codex gpt-6.2-sol)" ok codex_old_file_with_login
  echo 'not json' > "$HOME/.codex/auth.json"; echo '// comments' > "$HOME/.gemini/settings.json"
  assert_eq "$(check codex gpt-6.2-sol)" ok unreadable_auth_file_keeps_env_rule
  assert_eq "$(check gemini gemini-4-argon)" ok unreadable_settings_keep_env_rule
  assert_no "$KAITO_HOME/usage-consent.json"
}

test_usage_consent_stored_api_key_asks() {
  mk_usage
  secret=sk-test-do-not-print
  CODEX_HOME="$HOME/cx"; export CODEX_HOME; mkdir -p "$CODEX_HOME" "$HOME/.gemini"
  echo '{"auth_mode":"apikey","OPENAI_API_KEY":"'$secret'"}' > "$CODEX_HOME/auth.json"
  assert_eq "$(check codex gpt-6.2-sol 2>&1)" ask codex_login_with_api_key
  echo '{"OPENAI_API_KEY":"'$secret'"}' > "$CODEX_HOME/auth.json"
  assert_eq "$(check codex gpt-6.2-sol 2>&1)" ask codex_older_file_with_only_a_key
  node "$U" consent yes gpt-6.2-sol > /dev/null || exit 1
  assert_eq "$(check codex gpt-6.2-sol)" ok yes_holds
  for t in gemini-api-key vertex-ai compute-default-credentials; do
    echo '{"security":{"auth":{"selectedType":"'$t'"}}}' > "$HOME/.gemini/settings.json"
    assert_eq "$(check gemini gemini-4-argon)" ask "gemini $t"
  done
  echo '{"selectedAuthType":"gemini-api-key"}' > "$HOME/.gemini/settings.json"
  assert_eq "$(check gemini gemini-4-argon)" ask gemini_old_settings_key
  rm "$HOME/.gemini/settings.json"
  assert_eq "$(GOOGLE_GENAI_USE_VERTEXAI=true check gemini gemini-4-argon)" ask gemini_vertex_env
  assert_eq "$(check claude opus)" ok other_runners_unaffected
}

test_usage_consent_api_key_routes_ask() {
  mk_usage
  secret=sk-test-do-not-print
  assert_eq "$(ANTHROPIC_API_KEY=$secret check claude opus 2>&1)" ask claude_on_key
  assert_eq "$(OPENAI_API_KEY=$secret check codex gpt-6.2-sol 2>&1)" ask codex_on_key
  assert_eq "$(OPENAI_API_KEY=$secret check claude opus)" ok other_vendors_key
  assert_eq "$(GEMINI_API_KEY=$secret check gemini gemini-4-argon 2>&1)" ask gemini_on_key
  assert_eq "$(XAI_API_KEY=$secret check opencode xai/grok-4.7 2>&1)" ask opencode_on_key
  assert_eq "$(check opencode openrouter/qwen-max)" ask opencode_openrouter
  assert_eq "$(check api grok-4.7)" ask direct_api
  assert_eq "$(check some-new-runner m)" ask unknown_runner_is_not_assumed_free
  ANTHROPIC_API_KEY=$secret node "$U" consent yes opus > "$HOME/o" 2>&1
  ! grep -rq "$secret" "$HOME/o" "$KAITO_HOME" || exit 1
}
