# Issue-gate Owner-Approval Enforcement — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `issue-gate.yml` require that the `ready-for-dev` / `skip-issue-check` approval labels were applied by the repo **owner** (`@fr1j0`), not merely present.

**Architecture:** Extend the gate's single GraphQL query to also read each entity's `LABELED_EVENT` timeline (which carries the actor who applied each label). The latest matching event's actor must equal `$OWNER`. No permission API, no new token scope, no committed test harness — verification is local `jq` checks against canned JSON plus shellcheck plus dogfooding on this PR.

**Tech Stack:** GitHub Actions (`pull_request_target`), bash, `gh api graphql`, `jq`.

**Spec:** `docs/superpowers/specs/2026-06-04-issue-gate-owner-approval-design.md`

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `.github/workflows/issue-gate.yml` | The gate. Single GraphQL fetch → classify linked issues / PR skip label → sticky + exit code. | Rewrite the `run:` block: one fetch carrying labels **and** label-events for the PR and each linked issue; gate both label paths on owner-applied; extend sticky messages. |
| `docs/TRIAGE.md` | Maintainer-side process doc. | Rewrite "Label ownership" — gate now **enforces** owner-applied approval; note the owner-only limitation + the single extension point. |

No new scripts. No changes to the `on:`, `permissions:`, or `env:` blocks of the workflow.

---

## Task 1: Rewrite the gate `run:` block

**Files:**
- Modify: `.github/workflows/issue-gate.yml` (the `steps: - name: Run gate` → `run: |` block only; leave the header comment, `name:`, `on:`, `permissions:`, `jobs.gate.runs-on`, and the `env:` keys unchanged)

- [ ] **Step 1: Replace the entire `run: |` block**

Replace everything from `run: |` (the line after `shell: bash`) to the end of the file with the following block. Keep the same indentation level as the current `run: |` content (10 spaces for the first content line). The `env:` block above it (`GH_TOKEN`, `REPO`, `PR`, `OWNER`) stays exactly as-is.

```bash
        run: |
          set -euo pipefail

          MARKER='<!-- bitacora-issue-gate -->'
          NAME="${REPO#*/}"

          # ------------------------------------------------------------------
          # post_or_update_sticky: write the marker comment, or edit it in place
          # ------------------------------------------------------------------
          post_or_update_sticky() {
            local body="$1"
            local full="${MARKER}"$'\n'"${body}"
            local existing
            existing=$(gh api "repos/${REPO}/issues/${PR}/comments" --paginate \
              --jq ".[] | select(.user.login==\"github-actions[bot]\") | select(.body | startswith(\"${MARKER}\")) | .id" \
              | head -n1 || true)
            if [ -n "$existing" ]; then
              gh api -X PATCH "repos/${REPO}/issues/comments/${existing}" -f body="$full" >/dev/null
            else
              gh pr comment "$PR" --repo "$REPO" --body "$full" >/dev/null
            fi
          }

          # ------------------------------------------------------------------
          # Single fetch: PR labels + PR label-events, and for each linked
          # closing issue its labels + label-events. A LABELED_EVENT carries the
          # actor who applied each label, so the gate can require the OWNER's
          # approval (issue #92) instead of mere presence.
          #
          # timelineItems is capped at 100 LABELED_EVENTs per entity — far above
          # any real issue in this repo; latest-wins still holds for the page.
          # ------------------------------------------------------------------
          response=$(gh api graphql -f query='
            query($owner: String!, $name: String!, $number: Int!) {
              repository(owner: $owner, name: $name) {
                pullRequest(number: $number) {
                  labels(first: 30) { nodes { name } }
                  timelineItems(first: 100, itemTypes: [LABELED_EVENT]) {
                    nodes { ... on LabeledEvent { label { name } actor { login } createdAt } }
                  }
                  closingIssuesReferences(first: 20) {
                    nodes {
                      number
                      labels(first: 30) { nodes { name } }
                      timelineItems(first: 100, itemTypes: [LABELED_EVENT]) {
                        nodes { ... on LabeledEvent { label { name } actor { login } createdAt } }
                      }
                    }
                  }
                }
              }
            }' -F owner="$OWNER" -F name="$NAME" -F number="$PR")

          # pr_has_label <name>: true if the PR currently carries <name>.
          pr_has_label() {
            jq -e --arg L "$1" \
              '.data.repository.pullRequest.labels.nodes | any(.name==$L)' \
              <<<"$response" >/dev/null
          }

          # pr_label_actor <name>: login of the latest LABELED_EVENT actor for
          # <name> on the PR itself (empty if no such event).
          pr_label_actor() {
            jq -r --arg L "$1" '
              .data.repository.pullRequest.timelineItems.nodes
              | map(select(.label.name==$L))
              | sort_by(.createdAt) | last | .actor.login // empty
            ' <<<"$response"
          }

          # ------------------------------------------------------------------
          # Override: PR carries skip-issue-check — but only the OWNER's
          # application counts. A non-owner skip label is IGNORED (fall through
          # to the linked-issue check) with a note, never a hard block.
          # ------------------------------------------------------------------
          SKIP_NOTE=""
          if pr_has_label "skip-issue-check"; then
            skip_actor=$(pr_label_actor "skip-issue-check")
            if [ "$skip_actor" = "$OWNER" ]; then
              post_or_update_sticky "$(printf 'Gate skipped — `skip-issue-check` applied by the repo owner (@%s).' "$OWNER")"
              exit 0
            fi
            SKIP_NOTE="Note: \`skip-issue-check\` was ignored — it was not applied by the repo owner (@${OWNER})."$'\n\n'
          fi

          # ------------------------------------------------------------------
          # Linked closing issues: number, presence of ready-for-dev, and the
          # actor who most recently applied it. Tab-separated: "<num>\t<y|n>\t<actor>".
          # ------------------------------------------------------------------
          linked=$(jq -r '
            .data.repository.pullRequest.closingIssuesReferences.nodes[]
            | . as $n
            | ($n.labels.nodes | any(.name=="ready-for-dev")) as $present
            | ($n.timelineItems.nodes
                | map(select(.label.name=="ready-for-dev"))
                | sort_by(.createdAt) | last | .actor.login // "") as $actor
            | "\($n.number)\t\(if $present then "y" else "n" end)\t\($actor)"
          ' <<<"$response" || true)

          # ------------------------------------------------------------------
          # No linked issues at all -> fail
          # ------------------------------------------------------------------
          if [ -z "$linked" ]; then
            msg=$(cat <<'MSG' | sed 's/^          //'
          Gate failed — no linked issue found.

          Add `Closes #<N>` (or `Fixes #<N>` / `Resolves #<N>`) to the PR body, or link an
          issue manually in the right-hand sidebar. The linked issue must carry the
          `ready-for-dev` label, applied by the repo owner.

          See [CONTRIBUTING.md](../blob/main/CONTRIBUTING.md) for the full flow.
          MSG
            )
            post_or_update_sticky "${SKIP_NOTE}${msg}"
            exit 1
          fi

          # ------------------------------------------------------------------
          # Partition linked issues. Approved = ready-for-dev present AND the
          # latest applier is the owner. Anything else is unapproved.
          # ------------------------------------------------------------------
          approved=()
          unapproved=()
          while IFS=$'\t' read -r num present actor; do
            [ -z "$num" ] && continue
            if [ "$present" = "y" ] && [ "$actor" = "$OWNER" ]; then
              approved+=("$num")
            else
              unapproved+=("$num")
            fi
          done <<<"$linked"

          if [ "${#approved[@]}" -gt 0 ]; then
            list=$(IFS=,; echo "${approved[*]}" | sed 's/,/, #/g')
            post_or_update_sticky "${SKIP_NOTE}Gate passed — linked to owner-approved issue(s) #${list}."
            exit 0
          fi

          # ------------------------------------------------------------------
          # Linked issues exist but none are owner-approved -> fail
          # ------------------------------------------------------------------
          list=$(IFS=,; echo "${unapproved[*]}" | sed 's/,/, #/g')
          msg=$(cat <<MSG | sed 's/^          //'
          Gate failed — linked issue(s) #${list} are not approved by the repo owner.

          The \`ready-for-dev\` label must be applied by @${OWNER} (the repo owner). A label
          that is absent, or applied by anyone else, does not count — a maintainer needs to
          triage and apply it. See [CONTRIBUTING.md](../blob/main/CONTRIBUTING.md).
          MSG
          )
          post_or_update_sticky "${SKIP_NOTE}${msg}"
          exit 1
```

- [ ] **Step 2: Verify the classification logic locally with canned JSON**

This exercises the exact `jq` expressions from the workflow against synthetic GraphQL responses — no GitHub, no `gh`. Create a scratch file and run the assertions:

```bash
cat > /tmp/gate-sample.json <<'JSON'
{"data":{"repository":{"pullRequest":{
  "labels":{"nodes":[{"name":"enhancement"}]},
  "timelineItems":{"nodes":[]},
  "closingIssuesReferences":{"nodes":[
    {"number":92,
     "labels":{"nodes":[{"name":"ready-for-dev"},{"name":"enhancement"}]},
     "timelineItems":{"nodes":[
       {"label":{"name":"needs-triage"},"actor":{"login":"someone"},"createdAt":"2026-06-01T00:00:00Z"},
       {"label":{"name":"ready-for-dev"},"actor":{"login":"contributor"},"createdAt":"2026-06-01T10:00:00Z"},
       {"label":{"name":"ready-for-dev"},"actor":{"login":"fr1j0"},"createdAt":"2026-06-02T00:00:00Z"}
     ]}},
    {"number":50,
     "labels":{"nodes":[{"name":"ready-for-dev"}]},
     "timelineItems":{"nodes":[
       {"label":{"name":"ready-for-dev"},"actor":{"login":"contributor"},"createdAt":"2026-06-03T00:00:00Z"}
     ]}}
  ]}}}}}
JSON

response=$(cat /tmp/gate-sample.json)
linked=$(jq -r '
  .data.repository.pullRequest.closingIssuesReferences.nodes[]
  | . as $n
  | ($n.labels.nodes | any(.name=="ready-for-dev")) as $present
  | ($n.timelineItems.nodes
      | map(select(.label.name=="ready-for-dev"))
      | sort_by(.createdAt) | last | .actor.login // "") as $actor
  | "\($n.number)\t\(if $present then "y" else "n" end)\t\($actor)"
' <<<"$response")
echo "$linked"
```

Run: the command above.
Expected output (exactly):
```
92	y	fr1j0
50	y	contributor
```
This proves: latest-wins (issue 92's last applier `fr1j0` beats the earlier `contributor`), and a non-owner applier (issue 50, `contributor`) is surfaced as the actor — so the bash partition will mark 92 approved and 50 unapproved.

- [ ] **Step 3: Verify the owner partition decision**

```bash
OWNER=fr1j0
approved=(); unapproved=()
while IFS=$'\t' read -r num present actor; do
  [ -z "$num" ] && continue
  if [ "$present" = "y" ] && [ "$actor" = "$OWNER" ]; then approved+=("$num"); else unapproved+=("$num"); fi
done <<<"$linked"
echo "approved=${approved[*]:-} | unapproved=${unapproved[*]:-}"
```

Run: the command above.
Expected output (exactly):
```
approved=92 | unapproved=50
```

- [ ] **Step 4: Verify the skip-issue-check actor extraction**

```bash
# owner-applied skip -> should yield "fr1j0"
response='{"data":{"repository":{"pullRequest":{
  "labels":{"nodes":[{"name":"skip-issue-check"}]},
  "timelineItems":{"nodes":[{"label":{"name":"skip-issue-check"},"actor":{"login":"fr1j0"},"createdAt":"2026-06-04T00:00:00Z"}]},
  "closingIssuesReferences":{"nodes":[]}}}}}'
jq -r '.data.repository.pullRequest.timelineItems.nodes | map(select(.label.name=="skip-issue-check")) | sort_by(.createdAt) | last | .actor.login // empty' <<<"$response"
```

Run: the command above.
Expected output (exactly):
```
fr1j0
```

- [ ] **Step 5: Run shellcheck on the gate's shell**

The CI `test.yml` runs shellcheck on plugin scripts, not on workflow YAML. Extract the `run:` body and lint it directly:

```bash
cd /Users/fernandocastillo/Projects/bitacora
# pull the run-block body into a temp script (strip the 10-space YAML indent)
awk '/^        run: \|/{f=1;next} f{sub(/^          /,"");print}' .github/workflows/issue-gate.yml > /tmp/gate-body.sh
shellcheck --severity=warning /tmp/gate-body.sh; echo "exit=$?"
```

Run: the command above.
Expected: `exit=0` (no warning-or-higher findings). If shellcheck flags `SC2034` on `SKIP_NOTE` or array-related notices, confirm they are not present at `warning` severity; fix any genuine `warning`+ finding before continuing.

- [ ] **Step 6: Commit**

```bash
cd /Users/fernandocastillo/Projects/bitacora
git add .github/workflows/issue-gate.yml
git commit -m "feat(gate): require owner-applied approval labels (#92)"
```

---

## Task 2: Update `docs/TRIAGE.md` "Label ownership"

**Files:**
- Modify: `docs/TRIAGE.md` (the "## Label ownership" section, currently around lines 44–47)

- [ ] **Step 1: Replace the "Label ownership" section**

Find this block:

```markdown
## Label ownership

Only maintainers apply `ready-for-dev` and `skip-issue-check`. Contributors should not
self-apply these (the gate workflow only trusts maintainer labels in practice; we don't
hard-enforce this, but it's the social contract).
```

Replace it with:

```markdown
## Label ownership

Only the repo owner (@fr1j0) approves work. The `ready-for-dev` (on an issue) and
`skip-issue-check` (on a PR) labels **only count when the owner applied them** — the
issue-gate reads each label's `LABELED_EVENT` actor and fails the gate if anyone else
applied it. A non-owner `skip-issue-check` is ignored (the PR falls through to the normal
linked-issue check) rather than blocking. Self-applying these labels as a contributor will
not pass the gate.

This is intentionally owner-only. If a co-maintainer is added later, extend the owner
comparison (`actor == $OWNER`) in `.github/workflows/issue-gate.yml` to accept their login
as well.
```

- [ ] **Step 2: Confirm the edit landed**

Run:
```bash
cd /Users/fernandocastillo/Projects/bitacora
grep -n "only count when the owner applied them" docs/TRIAGE.md && ! grep -n "social contract" docs/TRIAGE.md && echo OK
```
Expected: a matching line for the new text, no remaining "social contract" line, and `OK` printed.

- [ ] **Step 3: Commit**

```bash
cd /Users/fernandocastillo/Projects/bitacora
git add docs/TRIAGE.md
git commit -m "docs(triage): gate enforces owner-applied approval (#92)"
```

---

## Task 3: Open the PR (dogfood validation)

**Files:** none (git/gh only)

- [ ] **Step 1: Push the branch**

```bash
cd /Users/fernandocastillo/Projects/bitacora
git push -u origin feat/issue-92-gate-owner-approval
```
Expected: branch pushed; no merge to `main` (branch-protected).

- [ ] **Step 2: Open the PR with the closing reference**

```bash
cd /Users/fernandocastillo/Projects/bitacora
gh pr create --base main --head feat/issue-92-gate-owner-approval \
  --title "feat(gate): require owner-applied approval labels" \
  --body "$(cat <<'BODY'
Closes #92

Hardens `issue-gate.yml` so `ready-for-dev` / `skip-issue-check` only pass the gate when
applied by the repo owner, by reading each label's `LABELED_EVENT` actor instead of mere
presence. Owner-only by design; non-owner `skip-issue-check` is ignored (falls through),
never a hard block. Docs updated in `docs/TRIAGE.md`. No token-scope or branch-protection
change.

Spec: `docs/superpowers/specs/2026-06-04-issue-gate-owner-approval-design.md`
Plan: `docs/superpowers/plans/2026-06-04-issue-gate-owner-approval.md`
BODY
)"
```
Expected: PR URL printed. Do **not** self-apply any label.

- [ ] **Step 3: Confirm the gate dogfoods green**

Wait for the `gate` check to run on the new PR, then:
```bash
cd /Users/fernandocastillo/Projects/bitacora
gh pr checks --watch
```
Expected: `gate` passes — #92's `ready-for-dev` was applied by `fr1j0` (the owner), so the hardened gate must report *"Gate passed — linked to owner-approved issue(s) #92."* If it fails, the gate logic is wrong; stop and debug before handing off for review.

- [ ] **Step 4: Hand off for owner review**

The PR cannot merge until @fr1j0 applies the code-owner approving review (`CODEOWNERS = * @fr1j0`) and merges. Report the PR URL and the gate result to the owner.

---

## Self-Review

**Spec coverage:**
- Owner-applied `ready-for-dev` (latest event, present + owner) → Task 1 partition. ✅
- Owner-applied `skip-issue-check`, non-owner ignored with note → Task 1 SKIP_NOTE path. ✅
- Fail-closed on present-but-no-event → `actor=""` ≠ `$OWNER` → unapproved. ✅
- Latest-wins on remove/re-add → `sort_by(.createdAt) | last` (verified Task 1 Step 2). ✅
- At-least-one owner-approved passes → `${#approved[@]} -gt 0`. ✅
- Extended sticky messages → Task 1. ✅
- Single GraphQL fetch, no extra round-trips, no new token scope → Task 1 query, `permissions:` untouched. ✅
- Timeline cap commented → Task 1 query comment. ✅
- Docs "Label ownership" rewrite + owner-only note → Task 2. ✅
- No new script / no committed harness → only `issue-gate.yml` + `docs/TRIAGE.md` modified. ✅
- Dogfood validation → Task 3 Step 3. ✅

**Placeholder scan:** No TBD/TODO; every code/command step shows full content and exact expected output. ✅

**Type/name consistency:** `pr_has_label`, `pr_label_actor`, `$OWNER`, `$response`, `linked`, `approved`/`unapproved`, `SKIP_NOTE` used consistently across steps and the doc reference (`actor == $OWNER`). ✅
