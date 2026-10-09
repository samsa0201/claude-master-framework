# Test-only runtime: no model, no network. tests/fake-worker.sh plays the worker.
rt_preflight() { :; }
rt_env() { echo "FAKE_ROLE=$role"; echo "FAKE_MODEL=$model"; echo "FAKE_BROWSER=$browser"; }
rt_cmd() { echo "$ROOT/tests/fake-worker.sh '$msg'"; }
RT_ONESHOT=${FAKE_ONESHOT:-}   # tests: pretend to be a one-shot runtime
