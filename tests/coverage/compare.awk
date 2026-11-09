# Coverage comment for a pull request: the base branch against the PR.
#
#   awk -v base_name=main -v base_sha=... -v head_sha=... -v run_url=... \
#       -f compare.awk BASE_LCOV HEAD_LCOV > comment.md
#
# Both files are lcov.info as written by report.awk (`make coverage`); only
# the SF/LF/LH records are read. BASE_LCOV may be empty (/dev/null) when the
# base has no coverage yet, and then only the PR's numbers are shown.
#
# The first line is a marker CI uses to find and update its own comment
# instead of adding a new one on every push.

BEGIN { side = 0; nf = 0 }

FNR == 1 { side++ }

/^SF:/ {
  f = substr($0, 4)
  if (!(f in seen)) { seen[f] = 1; order[++nf] = f }
  next
}
/^LF:/ { stmts[side, f] = substr($0, 4) + 0; has[side, f] = 1; next }
/^LH:/ { hit[side, f] = substr($0, 4) + 0; next }

function pct(c, n) { return n ? 100 * c / n : 0 }

function cell(s, f) {
  if (!((s, f) in has)) return "–"
  return sprintf("%.1f%%", pct(hit[s, f], stmts[s, f]))
}

function delta(f,    d) {
  if (!((1, f) in has) || !((2, f) in has)) return ""
  d = pct(hit[2, f], stmts[2, f]) - pct(hit[1, f], stmts[1, f])
  if (d > -0.05 && d < 0.05) return "±0"
  return sprintf("%+.1f", d)
}

END {
  # With an empty base file only one side was read: shift it to the PR side.
  if (side < 2) {
    for (i = 1; i <= nf; i++) {
      f = order[i]
      if ((1, f) in has) {
        stmts[2, f] = stmts[1, f]; hit[2, f] = hit[1, f]; has[2, f] = 1
        delete has[1, f]
      }
    }
  }

  for (i = 1; i <= nf; i++) {
    f = order[i]
    if ((1, f) in has) { bs += stmts[1, f]; bh += hit[1, f]; hasbase = 1 }
    if ((2, f) in has) { hs += stmts[2, f]; hh += hit[2, f] }
  }

  print "<!-- coverage-report -->"
  printf "### Coverage: %.1f%%", pct(hh, hs)
  if (hasbase) {
    d = pct(hh, hs) - pct(bh, bs)
    if (d > -0.05 && d < 0.05) printf " (unchanged from `%s`)", base_name
    else printf " (%+.1f%% from `%s`)", d, base_name
  }
  printf "\n\n"

  if (hasbase) {
    printf "| File | `%s` | This PR | Δ |\n", base_name
    print "|------|------:|------:|------:|"
    for (i = 1; i <= nf; i++) {
      f = order[i]
      line = sprintf("| `%s` | %s | %s | %s |", f, cell(1, f), cell(2, f), delta(f))
      # Bold the files whose coverage moved, so they stand out.
      if (delta(f) != "" && delta(f) != "±0") line = sprintf("| **`%s`** | %s | **%s** | **%s** |", f, cell(1, f), cell(2, f), delta(f))
      print line
    }
    printf "| **Total** | **%.1f%%** | **%.1f%%** | **%s** |\n", pct(bh, bs), pct(hh, hs), \
      (d > -0.05 && d < 0.05) ? "±0" : sprintf("%+.1f", d)
  } else {
    print "| File | Coverage |"
    print "|------|------:|"
    for (i = 1; i <= nf; i++) printf "| `%s` | %s |\n", order[i], cell(2, order[i])
    printf "| **Total** | **%.1f%%** |\n", pct(hh, hs)
    printf "\n`%s` has no coverage report yet, so there is nothing to compare against.\n", base_name
  }

  printf "\n<sub>Statements run by the bats suite (`make coverage`)"
  if (head_sha != "") printf " at %s", substr(head_sha, 1, 7)
  if (hasbase && base_sha != "") printf ", against `%s` at %s", base_name, substr(base_sha, 1, 7)
  printf "."
  if (run_url != "") printf " Per-line detail is in the [`coverage` artifact](%s).", run_url
  print "</sub>"
}
