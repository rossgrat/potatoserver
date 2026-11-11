/^  - hostname:/ {
  cms = ($0 == "  - hostname: cms.grattafiori.dev")
}
cms && /^    service:/ {
  if ($0 != "    service: http://127.0.0.1:3030") exit 2
  print "    service: http://127.0.0.1:80"
  changed++
  next
}
{ print }
END {
  if (changed != 1) exit 1
}
