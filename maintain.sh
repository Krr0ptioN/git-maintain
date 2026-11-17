#!/usr/bin/env bash
set -euo pipefail

# 1. Read input configuration
NOTIFY_USERS="${INPUT_NOTIFY_USERS:-}"
CREATE_ISSUE="${INPUT_CREATE_ISSUE:-true}"
ISSUE_TITLE="${INPUT_ISSUE_TITLE:-🛠️ Git Maintenance Statistics}"
STEP_SUMMARY="${INPUT_STEP_SUMMARY:-true}"
ENABLE_CRUFT="${INPUT_ENABLE_CRUFT:-true}"
THREADS="${INPUT_THREADS:-}"

# 2. Configure Git maintenance tasks
echo "::group::Configuring Git Maintenance"
git config maintenance.repack.enabled true
git config maintenance.gc.enabled true
git config maintenance.commit-graph.enabled true
git config maintenance.prefetch.enabled true
echo "::endgroup::"

# 3. Run Git maintenance
echo "::group::Running Git Maintenance"
git maintenance run || true
echo "::endgroup::"

# 4. Prepare repack flags
REPACK_ARGS=("-a" "-d")
if [ "$ENABLE_CRUFT" = "true" ]; then
    REPACK_ARGS+=("--cruft")
fi
if [ -n "$THREADS" ]; then
    REPACK_ARGS+=("--threads=$THREADS")
fi

echo "::group::Running Git Repack"
LOG_FILE=$(mktemp)
REPORT_FILE=$(mktemp)
trap 'rm -f "$LOG_FILE" "$REPORT_FILE"' EXIT

script -qec "git repack ${REPACK_ARGS[*]}" "$LOG_FILE" > /dev/null || true
echo "::endgroup::"

# 5. Parse progress metrics with awk into clean Markdown table
TABLE=$(tr '\r' '\n' < "$LOG_FILE" | awk '
BEGIN {
    print "| Operation | Value |"
    print "|:---|:---|"
    cruft_total = ""
}
/Enumerating objects: [0-9]+, done/ {
    match($0, /Enumerating objects: ([0-9]+)/, m)
    print "| Enumerating objects | " m[1] " |"
}
/Counting objects:.*done/ && !cruft {
    match($0, /Counting objects: ([^,]+)/, m)
    print "| Counting objects | " m[1] " |"
}
/Delta compression/ && !cruft {
    match($0, /([0-9]+) threads/, m)
    threads = (m[1] ? m[1] " threads" : "8 threads")
    print "| Delta compression | " threads " |"
}
/Compressing objects:.*done/ && !cruft {
    match($0, /Compressing objects: ([^,]+)/, m)
    print "| Compressing objects | " m[1] " |"
}
/Writing objects:.*done/ && !cruft {
    match($0, /Writing objects: ([^,]+)/, m)
    print "| Writing objects | " m[1] " |"
}
/^Total [0-9]+/ && /reused/ && !cruft {
    match($0, /Total ([0-9]+)/, m_tot)
    match($0, /reused ([^,]+)/, m_reu)
    match($0, /pack-reused ([^\n]+)/, m_pck)
    if (m_reu[1]) print "| Reused objects | " m_reu[1] " |"
    if (m_pck[1]) print "| pack-reused | " m_pck[1] " |"
    if (m_tot[1]) print "| Total objects | `" m_tot[1] "` |"
}
/Enumerating cruft objects:/ {
    cruft = 1
    match($0, /Enumerating cruft objects: ([0-9]+)/, m)
    print "| Enumerating cruft objects | " m[1] ", |"
}
/Traversing cruft objects:/ {
    match($0, /Traversing cruft objects: ([0-9]+)/, m)
    print "| Traversing cruft objects | " m[1] ", |"
}
/Counting objects:.*done/ && cruft {
    match($0, /Counting objects: ([^,]+)/, m)
    print "| Counting objects | " m[1] " |"
}
/Delta compression/ && cruft {
    match($0, /([0-9]+) threads/, m)
    threads = (m[1] ? "using up to " m[1] " threads" : "using up to 8 threads")
    print "| Delta compression | " threads " |"
}
/Compressing objects:.*done/ && cruft {
    match($0, /Compressing objects: ([^,]+)/, m)
    print "| Compressing objects | " m[1] " |"
}
/Writing objects:.*done/ && cruft {
    match($0, /Writing objects: ([^,]+)/, m)
    print "| Writing objects | " m[1] " |"
}
/^Total [0-9]+/ && /reused/ && cruft {
    cruft_total = $0
}
END {
    if (cruft_total != "") {
        print "\n" cruft_total
    }
}
')

# 6. Build notification line
NOTIFICATION_LINE=""
if [ -n "$NOTIFY_USERS" ]; then
    # Format usernames into @mentions
    MENTIONS=$(echo "$NOTIFY_USERS" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^@*//;s/^/@/' | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    NOTIFICATION_LINE="**Notification**: cc $MENTIONS"
fi

# 7. Construct final Markdown report
{
    echo "# 🛠️ Git Maintenance Statistics"
    echo ""
    if [ -n "$NOTIFICATION_LINE" ]; then
        echo "$NOTIFICATION_LINE"
        echo ""
    fi
    echo "$TABLE"
} > "$REPORT_FILE"

# 8. Append to GITHUB_STEP_SUMMARY if requested
if [ "$STEP_SUMMARY" = "true" ] && [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    cat "$REPORT_FILE" >> "$GITHUB_STEP_SUMMARY"
fi

# Print report to job logs
cat "$REPORT_FILE"

# 9. Set GitHub Action outputs
TOTAL_OBJECTS=$(grep -oE 'Total [0-9]+' "$LOG_FILE" | head -n 1 | awk '{print $2}' || echo "")
CRUFT_TOTAL=$(grep -oE 'Total [0-9]+' "$LOG_FILE" | tail -n 1 | awk '{print $2}' || echo "")

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "total_objects=${TOTAL_OBJECTS}" >> "$GITHUB_OUTPUT"
    echo "total_cruft=${CRUFT_TOTAL}" >> "$GITHUB_OUTPUT"
    # Multiline output for report_markdown
    EOF_DELIMITER=$(head -c 20 /dev/urandom | sha256sum | awk '{print $1}')
    echo "report_markdown<<${EOF_DELIMITER}" >> "$GITHUB_OUTPUT"
    cat "$REPORT_FILE" >> "$GITHUB_OUTPUT"
    echo "${EOF_DELIMITER}" >> "$GITHUB_OUTPUT"
fi

# 10. Notify maintainers via GitHub Issue
if [ "$CREATE_ISSUE" = "true" ] && [ -n "${GITHUB_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then
    echo "::group::Dispatching Issue Notification"
    EXISTING_ISSUE=$(gh issue list --search "$ISSUE_TITLE in:title" --json number --jq '.[0].number' 2>/dev/null || true)
    
    # Extract first assignee if user requested
    FIRST_USER=$(echo "$NOTIFY_USERS" | tr ',' '\n' | head -n 1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^@*//')

    if [ -n "$EXISTING_ISSUE" ]; then
        gh issue comment "$EXISTING_ISSUE" --body-file "$REPORT_FILE" || true
        echo "Posted maintenance statistics comment to issue #$EXISTING_ISSUE"
    else
        ISSUE_CMD=("gh" "issue" "create" "--title" "$ISSUE_TITLE" "--body-file" "$REPORT_FILE")
        if [ -n "$FIRST_USER" ]; then
            ISSUE_CMD+=("--assignee" "$FIRST_USER")
        fi
        "${ISSUE_CMD[@]}" || true
        echo "Created new maintenance tracking issue: $ISSUE_TITLE"
    fi
    echo "::endgroup::"
fi
