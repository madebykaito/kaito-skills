#!/bin/sh
. "$(dirname "$0")/lib.sh"
M="$REPO/helpmekaito/scripts/kaito-models.mjs"
m() { node "$M" "$@"; }

# A temp home with five stub agent CLIs first on PATH: claude, codex (with its models cache),
# cursor-agent, opencode and a gemini laid out like an npm install, its model ids in a bundle file.
mk_agents() {
  mk_home
  g="$HOME/npm"; b="$g/node_modules/@google/gemini-cli/bundle"
  mkdir -p "$b" "$HOME/.codex"
  printf '#!/bin/sh\nexit 0\n' > "$g/gemini"; chmod +x "$g/gemini"
  cat > "$b/chunk-TEST.js" <<'EOF'
var DEFAULT_GEMINI_MODEL = "gemini-2.5-pro";
var PREVIEW_GEMINI_MODEL = "gemini-3-pro-preview";
var PREVIEW_GEMINI_3_1_MODEL = "gemini-3.1-pro-preview";
var PREVIEW_GEMINI_3_1_CUSTOM_TOOLS_MODEL = "gemini-3.1-pro-preview-customtools";
var DEFAULT_GEMINI_FLASH_MODEL = "gemini-2.5-flash";
var PREVIEW_GEMINI_FLASH_MODEL = "gemini-3-flash-preview";
var SECONDARY_GEMINI_3_5_FLASH_MODEL = "gemini-3-flash";
var DEFAULT_GEMINI_FLASH_LITE_MODEL = "gemini-3.1-flash-lite";
var DEFAULT_GEMINI_EMBEDDING_MODEL = "gemini-embedding-001";
var IMAGE_MODEL = "gemini-2.5-flash-image";
var fixtures = ["gemini-9001-super-duper", "gemini-9-pro", "gemini-3-flash-base"];
EOF
  cat > "$HOME/.codex/models_cache.json" <<'EOF'
{"models":[{"slug": "gpt-6.2-sol"},{"slug": "gpt-6.1-sol"},{"slug": "gpt-6.2-astra"},{"slug": "gpt-6.1-terra"},
{"slug": "gpt-6-luna"},{"slug": "gpt-5.6-luna"},{"slug": "gpt-reserve"},{"slug": "codex-auto-review"}]}
EOF
  PATH="$g:$TESTS_DIR/stubs/agents:$PATH"; export PATH
}
has_line() { printf '%s\n' "$1" | grep -qxF "$2" || { echo "  no line '$2' in:"; echo "$1"; exit 1; }; }

# The rule reads the family word, never the version. Imported, so the export is tested and must print nothing itself.
test_tier_rule() {
  mk_home
  out=$(node --input-type=module -e '
    const { tierOf } = await import((await import("node:url")).pathToFileURL(process.argv[2]).href);
    const want = {
      light: ["haiku", "claude-haiku-5-5", "claude-agent/claude-haiku-4-5-20251001", "gpt-6-luna", "gpt-5.4-mini", "gpt-5.4-nano-none",
        "gemini-3.1-flash-lite", "gemini-2.5-flash-lite", "gemini-4-hydrogen-low"],
      standard: ["sonnet", "claude-sonnet-5-5-medium", "claude-4.5-sonnet", "gpt-6.1-terra", "openai/gpt-5.6-terra-fast",
        "gemini-3.5-flash", "gemini-3-flash-preview", "deepseek-v41-flash-1017-high"],
      hard: ["opus", "claude-opus-5-5-thinking-max-fast", "claude-4.6-opus", "gpt-6.2-sol", "gemini-2.5-pro",
        "gemini-3.1-pro-preview", "cursor-acp/gemini-4-argon-high"],
      frontier: ["fable", "claude-fable-5-2", "gpt-6.2-astra", "openai/gpt-6-astra-fast", "gemini-4-carbon-medium", "gemini-9-ultra"],
      null: ["grok-4.7", "xai/grok-4.20-0309-reasoning", "gpt-5.5", "gpt-5.3-codex", "composer-2.5", "kimi-k3", "glm-5.2-max",
        "muse-spark-1.3-minimal", "gemini-4-neon", "gpt-reserve", "auto", "qwen3.5:latest", ""],
    };
    let bad = 0;
    for (const [tier, ids] of Object.entries(want)) for (const id of ids) {
      if (String(tierOf(id)) !== tier) { bad = 1; console.log(`${id}: got ${tierOf(id)}, want ${tier}`); }
    }
    console.log(bad ? "bad" : "ok");' import "$M")
  assert_eq "$out" ok rule
  assert_eq "$(m tier claude-opus-5-5)" hard cli
  rc=0; m resolve openai huge > /dev/null 2>&1 || rc=$?
  assert_eq "$rc" 2 unknown_tier_is_usage
}

test_resolve_picks_newest() {
  mk_agents
  assert_eq "$(m resolve anthropic hard)" "claude opus" alias_is_newest
  assert_eq "$(m resolve openai hard)" "codex gpt-6.2-sol" highest_version_across_runners
  assert_eq "$(m resolve openai light)" "codex gpt-6-luna" by_number_not_text
  assert_eq "$(m resolve codex frontier)" "codex gpt-6.2-astra" runner
  assert_eq "$(m resolve google hard)" "cursor-agent gemini-4-argon-medium" vendor_across_runners
  # Gemini: read from the installed bundle. 3.1 preview beats 2.5; at the same version the non-preview id wins.
  assert_eq "$(m resolve gemini hard)" "gemini gemini-3.1-pro-preview" gemini_newest
  assert_eq "$(m resolve gemini standard)" "gemini gemini-3-flash" non_preview_first
  assert_eq "$(m resolve gemini light)" "gemini gemini-3.1-flash-lite" gemini_light
  # A runner that reaches several vendors answers one line for each; the plain effort of the newest wins.
  out=$(m resolve cursor-agent hard)
  has_line "$out" "cursor-agent claude-opus-5-5-medium"
  has_line "$out" "cursor-agent gpt-5.6-sol-high"
  has_line "$out" "cursor-agent gemini-4-argon-medium"
  assert_eq "$(printf '%s\n' "$out" | grep -c .)" 3 one_per_vendor
  assert_eq "$(m resolve opencode hard | grep openai)" "opencode openai/gpt-6.1-sol" not_the_fast_variant
  # Privacy: a NO ZDR listing and a free tier are never picked.
  assert_eq "$(m resolve cursor-agent frontier)" "host: no frontier model reachable for cursor-agent today; use the host's model" no_zdr
  assert_eq "$(m resolve opencode standard)" "opencode openai/gpt-5.6-terra" no_free_tier
  out=$(sh "$REPO/helpmekaito/scripts/models-available.sh" gemini)
  has_line "$out" "  gemini: yes"
  has_line "$out" "  gemini-2.5-pro"
  has_line "$out" "  gemini-4-argon-medium - Gemini 4 Argon  Medium"
  printf '%s\n' "$out" | grep -q 'customtools\|embedding\|image\|9001\|base' && { echo "  junk gemini ids listed"; echo "$out"; exit 1; }
  has_line "$(sh "$REPO/helpmekaito/scripts/models-available.sh" astra)" "  gpt-6.2-astra"
}

test_failed_today_is_skipped() {
  mk_agents
  assert_eq "$(m fail codex gpt-6.2-sol)" "failed today: codex gpt-6.2-sol" recorded
  assert_eq "$(m resolve openai hard)" "codex gpt-6.1-sol" next_newest
  m fail codex gpt-6.1-sol > /dev/null
  assert_eq "$(m resolve openai hard)" "opencode openai/gpt-6.1-sol" other_runner_still_tried
  # Every effort of a failed model is the same model.
  m fail cursor-agent claude-opus-5-5-medium > /dev/null
  assert_eq "$(m resolve cursor-agent hard | grep claude)" "cursor-agent claude-opus-5-thinking-high" all_efforts_skipped
  # Yesterday's failures no longer count.
  f="$KAITO_HOME/model-failures.json"
  grep -q '"codex gpt-6.2-sol"' "$f" || { cat "$f"; exit 1; }
  sed 's/"date": "[0-9-]*"/"date": "2000-01-01"/' "$f" > "$f.new" && mv "$f.new" "$f"
  grep -q 2000-01-01 "$f" || { cat "$f"; exit 1; }
  assert_eq "$(m resolve openai hard)" "codex gpt-6.2-sol" old_failure_forgotten
  m fail codex gpt-6.1-sol > /dev/null
  grep -q 'gpt-6.2-sol' "$f" && { echo "  old failures kept"; cat "$f"; exit 1; }
  assert_eq "$(m resolve openai hard)" "codex gpt-6.2-sol" only_today_counts
}

test_unknown_name_falls_back_to_host() {
  mk_agents
  assert_eq "$(m tier grok-4.7)" "host: the tier rule cannot place \"grok-4.7\"; use the host's model" tier
  assert_eq "$(m resolve xai hard)" "host: no hard model reachable for xai today; use the host's model" no_family_word
  assert_eq "$(m resolve mistral standard)" "host: no standard model reachable for mistral today; use the host's model" unknown_vendor
  # The gemini bundle cannot be found: no models, no error.
  rm -rf "$HOME/npm/node_modules"
  assert_eq "$(m resolve gemini hard)" "host: no hard model reachable for gemini today; use the host's model" no_bundle
  has_line "$(m list)" "MODELS gemini (read from the installed CLI; none means its bundle was not found)"
}

test_detect_stores_the_list() {
  mk_agents
  case "$(m detect)" in "agents: claude codex gemini cursor-agent opencode"*) ;; *) echo "  detect: $(m detect)"; exit 1 ;; esac
  node "$REPO/helpmekaito/scripts/kaito-json.mjs" get "$KAITO_HOME/agents.json" agents | grep -q '"claude","codex","gemini","cursor-agent","opencode"' ||
    { cat "$KAITO_HOME/agents.json"; exit 1; }
  # The stored list is used for a day, then found again.
  echo "{\"at\": $(($(date +%s) * 1000)), \"agents\": [\"claude\"]}" > "$KAITO_HOME/agents.json"
  assert_eq "$(m agents)" "agents: claude" stored
  assert_eq "$(m resolve codex hard)" "host: codex is not installed here; use the host's model" stored_list_decides
  echo "{\"at\": $(($(date +%s) * 1000 - 90000000)), \"agents\": [\"claude\"]}" > "$KAITO_HOME/agents.json"
  assert_eq "$(m resolve codex hard)" "codex gpt-6.2-sol" refreshed_after_a_day
  case "$(m agents)" in "agents: claude codex gemini cursor-agent opencode"*) ;; *) echo "  agents: $(m agents)"; exit 1 ;; esac
}

test_setup_lists_agents() {
  mk_agents
  R="$(mktemp -d)/kaito-skills"
  node "$REPO/helpmekaito/scripts/kaito-sync.mjs" mirror -x .git -x ./gstack -x ./.superpowers -x node_modules "$REPO" "$R"
  "$R/setup" --yes --no-gstack --no-codegraph > "$HOME/out" 2>&1 || { cat "$HOME/out"; exit 1; }
  grep -q '^agents: claude codex gemini cursor-agent opencode' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  assert_file "$KAITO_HOME/agents.json"
  # --upgrade finds them again, however fresh the stored list is.
  echo "{\"at\": $(($(date +%s) * 1000)), \"agents\": []}" > "$KAITO_HOME/agents.json"
  "$R/setup" --upgrade --no-gstack --no-codegraph > "$HOME/out" 2>&1 || { cat "$HOME/out"; exit 1; }
  grep -q '^agents: claude codex gemini cursor-agent opencode' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  grep -q '"codex"' "$KAITO_HOME/agents.json" || { cat "$KAITO_HOME/agents.json"; exit 1; }
}
