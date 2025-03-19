#!/usr/bin/env fish

set tests (status dirname)/*_test.fish
echo 1..(count $tests)

for test in $tests
  set test_txt (string replace .fish .txt $test)
  fish $test | sh (status dirname)/../tapview/tapdiffer (path basename $test) $test_txt
end
