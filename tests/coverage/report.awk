# Coverage report for `make coverage`.
#
#   awk -v out=coverage -v min=0 -f report.awk TRACE SCRIPT...
#
# TRACE holds one "file:line" per executed command, as written by trace.bash
# and trace.zsh. Paths are matched to the SCRIPTs by basename, which also
# folds in copies such as the trimmed system_stats.sh the tests source from a
# temp dir.
#
# Shell has no standard notion of an executable line, so each script is read
# with a small scanner that tracks quotes, parens and heredocs and groups
# lines into statements. A statement is a command that starts on its own line
# plus any lines it continues onto (trailing \ | && ||, an open quote or
# paren, a heredoc body). Lines that are only structure (fi, done, }, then,
# case patterns, function headers) and comments don't count. A statement is
# covered when any of its lines was traced.
#
# Writes OUT/lcov.info (for editor gutters, and what compare.awk reads for
# the PR comment), OUT/summary.md, and OUT/annotated/<script> with each line
# marked "> " (ran), "! " (never ran) or "  " (not a statement). Prints a
# table and exits 1 if total coverage is below MIN percent.

BEGIN {
  if (out == "") out = "coverage"
  if (min == "") min = 0
  for (i = 2; i < ARGC; i++) want[ARGV[i]] = 1
  nfiles = 0
  cur = ""
}

FILENAME == ARGV[1] {
  # Split on the last colon: paths may contain colons, line numbers can't.
  s = $0; p = 0
  while ((k = index(s, ":")) > 0) { p += k; s = substr(s, k + 1) }
  if (p == 0) next
  path = substr($0, 1, p - 1); ln = substr($0, p + 1)
  sub(/.*\//, "", path)
  if ((path in want) && ln ~ /^[0-9]+$/) hits[path, ln + 0]++
  next
}

FNR == 1 {
  if (cur != "") finish()
  start_file(FILENAME)
}

{ classify($0) }

END {
  if (cur != "") finish()
  report()
}

# --- scanning --------------------------------------------------------------

function start_file(f) {
  cur = f; nlines = 0
  st = ""          # open contexts: S '' / A $'' / D "" / B `` / P ( $( / R (( $((
  hdq = ""         # heredoc terminators seen on the current line, "word|tabs;..."
  inhd = 0; hdterm = ""; hdtabs = 0
  contnext = 0     # the previous line ended in \ | && ||
  curhead = 0
  delete kind; delete head; delete src
}

function top() { return substr(st, length(st), 1) }
function push(c) { st = st c }
function pop() { st = substr(st, 1, length(st) - 1) }
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }

# Scan one line, updating st and hdq. Sets g_code (the line minus any
# comment), g_casepos (position just past a ")" that closes a case pattern,
# or 0) and g_esc (the line ends in a backslash outside quotes).
function scan(line,    i, n, c, c2, t, j, q, w, dash, prev) {
  n = length(line); g_code = line; g_casepos = 0; g_esc = 0
  for (i = 1; i <= n; i++) {
    c = substr(line, i, 1); c2 = substr(line, i + 1, 1); t = top()
    if (t == "S") { if (c == "'") pop(); continue }
    if (t == "A") { if (c == "\\") i++; else if (c == "'") pop(); continue }
    if (t == "B") { if (c == "\\") i++; else if (c == "`") pop(); continue }
    if (t == "D") {
      if (c == "\\") i++
      else if (c == "\"") pop()
      else if (c == "`") push("B")
      else if (c == "$" && c2 == "(") {
        if (substr(line, i + 2, 1) == "(") { push("R"); push("R"); i += 2 }
        else { push("P"); i++ }
      }
      continue
    }
    # Code: the top level, inside ( ) or $( ), or arithmetic.
    if (c == "\\") { if (i == n) g_esc = 1; i++; continue }
    if (c == "'") { push("S"); continue }
    if (c == "\"") { push("D"); continue }
    if (c == "`") { push("B"); continue }
    if (c == "$" && c2 == "'") { push("A"); i++; continue }
    if (c == "(") {
      if (c2 == "(") { push("R"); push("R"); i++ } else push(t == "R" ? "R" : "P")
      continue
    }
    if (c == ")") {
      if (t == "P" || t == "R") pop()
      else if (st == "" && !g_casepos) g_casepos = i + 1
      continue
    }
    if (t == "R") continue
    if (c == "#") {
      prev = i == 1 ? " " : substr(line, i - 1, 1)
      if (prev ~ /[ \t;&|]/) { g_code = substr(line, 1, i - 1); return }
      continue
    }
    if (c == "<" && c2 == "<") {
      if (substr(line, i + 2, 1) == "<") { i += 2; continue }   # here-string
      j = i + 2; dash = 0
      if (substr(line, j, 1) == "-") { dash = 1; j++ }
      while (substr(line, j, 1) ~ /[ \t]/) j++
      q = substr(line, j, 1); w = ""
      if (q == "'" || q == "\"") {
        j++
        while (j <= n && substr(line, j, 1) != q) { w = w substr(line, j, 1); j++ }
      } else {
        if (q == "\\") j++
        while (j <= n && substr(line, j, 1) ~ /[A-Za-z0-9_]/) { w = w substr(line, j, 1); j++ }
        j--
      }
      if (w != "") hdq = hdq w "|" dash ";"
      i = j
      continue
    }
  }
}

function next_heredoc(    e) {
  e = index(hdq, ";")
  split(substr(hdq, 1, e - 1), parts, "|")
  hdterm = parts[1]; hdtabs = parts[2] + 0; inhd = 1
  hdq = substr(hdq, e + 1)
}

function classify(line,    l, cont, t, code) {
  nlines++; src[nlines] = line; l = nlines

  if (inhd) {
    kind[l] = curhead ? "cont" : "none"; head[l] = curhead
    t = line; if (hdtabs) sub(/^\t+/, "", t)
    if (t == hdterm) { inhd = 0; if (hdq != "") next_heredoc() }
    return
  }

  cont = (st != "" || contnext)
  scan(line)
  code = g_code

  if (cont) {
    kind[l] = curhead ? "cont" : "none"; head[l] = curhead
  } else {
    t = g_casepos ? substr(code, g_casepos) : code
    t = trim(t)
    while (t ~ /^(then|do|else|\{|;;|;&|;\||;)([ \t;]|$)/) {
      sub(/^(then|do|else|\{|;;|;&|;\||;)/, "", t); t = trim(t)
    }
    if (t == "" ||
        t ~ /^(fi|done|esac|\})([ \t;|&<>)]|$)/ ||
        t ~ /^(function[ \t]+)?[A-Za-z_][A-Za-z0-9_:.+-]*[ \t]*\(\)[ \t]*\{?$/ ||
        t ~ /^function[ \t]+[A-Za-z_][A-Za-z0-9_:.+-]*[ \t]*\{?$/ ||
        t ~ /^\(\)[ \t]*\{?$/) {
      kind[l] = "none"; head[l] = 0; curhead = 0
    } else {
      kind[l] = "head"; head[l] = l; curhead = l
    }
  }

  t = trim(code)
  contnext = (g_esc || t ~ /(\||&&)$/)
  if (hdq != "") next_heredoc()
}

# --- output ----------------------------------------------------------------

function finish(    l, h, n, covered, missed, ranges, rs, re, prevmiss, cnt, ann, lc) {
  # Hits on any line of a statement count for the statement.
  delete shits
  for (l = 1; l <= nlines; l++) {
    h = head[l]
    if (h && ((cur, l) in hits) && hits[cur, l] > shits[h]) shits[h] = hits[cur, l]
  }

  n = 0; covered = 0; ranges = ""; rs = 0; re = 0
  lc = out "/lcov.info"
  printf "TN:\nSF:%s\n", cur >> lc
  for (l = 1; l <= nlines; l++) {
    if (kind[l] != "head") continue
    n++; cnt = shits[l] + 0
    printf "DA:%d,%d\n", l, cnt >> lc
    if (cnt > 0) {
      covered++
      if (rs) { ranges = add_range(ranges, rs, re); rs = 0 }
    } else {
      if (!rs) rs = l
      re = l
    }
  }
  if (rs) ranges = add_range(ranges, rs, re)
  printf "LF:%d\nLH:%d\nend_of_record\n", n, covered >> lc
  close(lc)

  ann = out "/annotated/" cur
  for (l = 1; l <= nlines; l++) {
    if (kind[l] == "none") mark = "  "
    else mark = shits[head[l]] > 0 ? "> " : "! "
    print mark src[l] > ann
  }
  close(ann)

  nfiles++
  fname[nfiles] = cur; fstmts[nfiles] = n; fmiss[nfiles] = n - covered; franges[nfiles] = ranges
  tstmts += n; tcov += covered
}

function add_range(r, a, b) {
  return r (r == "" ? "" : ", ") (a == b ? a : a "-" b)
}

function pct(c, n) { return n ? sprintf("%.0f%%", 100 * c / n) : "-" }

function clip(s, w) { return length(s) <= w ? s : substr(s, 1, w - 2) " …" }

function report(    i, fmt, sum, total) {
  fmt = "%-24s %6s %6s %6s   %s\n"
  printf fmt, "File", "Stmts", "Miss", "Cover", "Missing"
  printf "%s\n", "------------------------------------------------------------------------------"
  for (i = 1; i <= nfiles; i++)
    printf fmt, fname[i], fstmts[i], fmiss[i], pct(fstmts[i] - fmiss[i], fstmts[i]), clip(franges[i], 40)
  printf "%s\n", "------------------------------------------------------------------------------"
  printf fmt, "TOTAL", tstmts, tstmts - tcov, pct(tcov, tstmts), ""
  printf "\nPer-line detail: %s/annotated/   lcov: %s/lcov.info\n", out, out

  sum = out "/summary.md"
  print "| File | Stmts | Miss | Cover |" > sum
  print "|------|------:|-----:|------:|" > sum
  for (i = 1; i <= nfiles; i++)
    printf "| `%s` | %d | %d | %s |\n", fname[i], fstmts[i], fmiss[i], pct(fstmts[i] - fmiss[i], fstmts[i]) > sum
  printf "| **Total** | **%d** | **%d** | **%s** |\n", tstmts, tstmts - tcov, pct(tcov, tstmts) > sum
  close(sum)

  total = tstmts ? 100 * tcov / tstmts : 100
  if (total < min + 0) {
    printf "\nCoverage %.1f%% is below the required %s%%\n", total, min
    exit 1
  }
}
