package agent

import (
	"context"
	"fmt"
	"strings"
	"testing"

	"github.com/nextlevelbuilder/goclaw/internal/pipeline"
	"github.com/nextlevelbuilder/goclaw/internal/providers"
	"github.com/nextlevelbuilder/goclaw/internal/tools"
)

// runToolResults feeds n tool results through processToolResult and returns the
// outputs of the last call.
func runToolResults(t *testing.T, rs *runState, n int, args func(i int) map[string]any, result string) ([]providers.Message, toolResultAction) {
	t.Helper()
	l := newTestLoopForToolCallbacks(func(AgentEvent) {})
	req := &RunRequest{RunID: "run-force-final"}
	var warnings []providers.Message
	var action toolResultAction
	for i := range n {
		tc := providers.ToolCall{ID: fmt.Sprintf("tc-%d", i), Name: "vault_search", Arguments: args(i)}
		_, warnings, action = l.processToolResult(context.Background(), rs, req, func(AgentEvent) {},
			tc, "vault_search", &tools.Result{ForLLM: result}, false)
	}
	return warnings, action
}

func assertForceFinal(t *testing.T, rs *runState, warnings []providers.Message, action toolResultAction) {
	t.Helper()
	if action != toolResultWarning {
		t.Errorf("action = %v, want toolResultWarning (no break)", action)
	}
	if !rs.forceFinal {
		t.Error("forceFinal = false, want true")
	}
	if rs.loopKilled {
		t.Error("loopKilled = true, want false (run must get one more answer iteration)")
	}
	if rs.finalContent != "" {
		t.Errorf("finalContent = %q, want empty (detector text must not reach the user)", rs.finalContent)
	}
	if len(warnings) == 0 || !strings.Contains(warnings[len(warnings)-1].Content, "Do not call any more tools") {
		t.Errorf("last warning = %v, want force-final note", warnings)
	}
}

// Trace 01a151bf: six searches with different args, all "No results found".
func TestProcessToolResult_SameResultCritical_ForcesFinalAnswer(t *testing.T) {
	t.Parallel()
	rs := &runState{}
	warnings, action := runToolResults(t, rs, sameResultCritical,
		func(i int) map[string]any { return map[string]any{"query": fmt.Sprintf("q%d", i)} },
		"No results found.")
	assertForceFinal(t, rs, warnings, action)
}

func TestProcessToolResult_SameArgsCritical_ForcesFinalAnswer(t *testing.T) {
	t.Parallel()
	rs := &runState{}
	warnings, action := runToolResults(t, rs, toolLoopCriticalThreshold,
		func(int) map[string]any { return map[string]any{"query": "same"} },
		"No results found.")
	assertForceFinal(t, rs, warnings, action)
}

func TestCheckReadOnlyStreak_Critical_ForcesFinalAnswer(t *testing.T) {
	t.Parallel()
	l := newTestLoopForToolCallbacks(func(AgentEvent) {})
	rs := &runState{}
	rs.loopDetector.readOnlyStreak = readOnlyStreakCritical
	rs.loopDetector.readOnlyUnique = 1

	note, shouldBreak := l.checkReadOnlyStreak(rs, &RunRequest{RunID: "run-ro"})
	if shouldBreak {
		t.Error("shouldBreak = true, want false")
	}
	if !rs.forceFinal || rs.loopKilled || rs.finalContent != "" {
		t.Errorf("forceFinal=%v loopKilled=%v finalContent=%q", rs.forceFinal, rs.loopKilled, rs.finalContent)
	}
	if note == nil || !strings.Contains(note.Content, "Do not call any more tools") {
		t.Errorf("note = %v, want force-final note", note)
	}
}

func TestSyncBridgeToState_CopiesForceFinalWithoutContent(t *testing.T) {
	t.Parallel()
	state := &pipeline.RunState{}
	syncBridgeToState(&runState{forceFinal: true}, state, toolResultWarning)
	if !state.Tool.ForceFinal {
		t.Error("ForceFinal not copied to pipeline state")
	}
	if state.Tool.LoopKilled || state.Observe.FinalContent != "" {
		t.Errorf("LoopKilled=%v FinalContent=%q, want false/empty", state.Tool.LoopKilled, state.Observe.FinalContent)
	}
}

func TestMakeBuildFilteredTools_ForceFinal_NoTools(t *testing.T) {
	t.Parallel()
	l := newTestLoopForToolCallbacks(func(AgentEvent) {})
	build := l.makeBuildFilteredTools(&RunRequest{RunID: "run-tools"})
	state := &pipeline.RunState{}
	state.Tool.ForceFinal = true

	defs, err := build(state)
	if err != nil {
		t.Fatalf("build error: %v", err)
	}
	if len(defs) != 0 {
		t.Errorf("tool defs = %d, want 0 when ForceFinal", len(defs))
	}
}
