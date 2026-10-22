package pipeline

import (
	"context"
	"testing"

	"github.com/nextlevelbuilder/goclaw/internal/i18n"
	"github.com/nextlevelbuilder/goclaw/internal/providers"
	"github.com/nextlevelbuilder/goclaw/internal/store"
)

// --- Loop guard: ForceFinal gives the model one tool-less answer iteration ---

func TestToolStage_ForceFinal_FinishesBatchWithoutBreak(t *testing.T) {
	t.Parallel()
	executed := 0
	deps := &PipelineDeps{
		Config: PipelineConfig{MaxToolCalls: 100},
		ExecuteToolCall: func(_ context.Context, state *RunState, _ providers.ToolCall) ([]providers.Message, error) {
			executed++
			state.Tool.ForceFinal = true
			return []providers.Message{{Role: "tool", Content: "No results found."}}, nil
		},
	}
	stage := NewToolStage(deps)
	state := defaultState()
	state.Think.LastResponse = &providers.ChatResponse{
		ToolCalls: []providers.ToolCall{{ID: "1", Name: "vault_search"}, {ID: "2", Name: "vault_search"}},
	}

	if err := stage.Execute(context.Background(), state); err != nil {
		t.Fatalf("Execute() error: %v", err)
	}
	if stage.Result() != Continue {
		t.Errorf("Result() = %v, want Continue so the next iteration can answer", stage.Result())
	}
	if executed != 2 {
		t.Errorf("executed = %d, want 2 (every tool call needs a result)", executed)
	}
}

func TestThinkStage_ForceFinal_DropsToolCalls(t *testing.T) {
	t.Parallel()
	var sentTools int
	deps := &PipelineDeps{
		Config:             PipelineConfig{MaxIterations: 10, MaxTokens: 1000},
		BuildFilteredTools: func(*RunState) ([]providers.ToolDefinition, error) { return nil, nil },
		CallLLM: func(_ context.Context, _ *RunState, req providers.ChatRequest) (*providers.ChatResponse, error) {
			sentTools = len(req.Tools)
			return &providers.ChatResponse{
				Content:      "Chưa có thông tin trong tài liệu SSP.",
				ToolCalls:    []providers.ToolCall{{ID: "x", Name: "vault_search"}},
				FinishReason: "tool_calls",
			}, nil
		},
	}
	stage := NewThinkStage(deps)
	state := defaultState()
	state.Iteration = 3
	state.Tool.ForceFinal = true

	if err := stage.Execute(context.Background(), state); err != nil {
		t.Fatalf("Execute() error: %v", err)
	}
	if sentTools != 0 {
		t.Errorf("tools sent = %d, want 0", sentTools)
	}
	if stage.Result() != BreakLoop {
		t.Errorf("Result() = %v, want BreakLoop", stage.Result())
	}
	if n := len(state.Think.LastResponse.ToolCalls); n != 0 {
		t.Errorf("tool calls kept = %d, want 0", n)
	}
}

func TestFinalizeStage_ForceFinal_EmptyContent_LoopStoppedFallback(t *testing.T) {
	t.Parallel()
	ctx := store.WithLocale(context.Background(), "vi")
	stage := NewFinalizeStage(&PipelineDeps{})
	state := defaultState()
	state.Tool.ForceFinal = true

	if err := stage.Execute(ctx, state); err != nil {
		t.Fatalf("Execute() error: %v", err)
	}
	want := i18n.T("vi", i18n.MsgLoopStoppedFallback)
	if state.Observe.FinalContent != want {
		t.Errorf("FinalContent = %q, want %q", state.Observe.FinalContent, want)
	}
}

func TestFinalizeStage_ForceFinal_KeepsModelAnswer(t *testing.T) {
	t.Parallel()
	stage := NewFinalizeStage(&PipelineDeps{})
	state := defaultState()
	state.Tool.ForceFinal = true
	state.Observe.FinalContent = "model answer"

	if err := stage.Execute(context.Background(), state); err != nil {
		t.Fatalf("Execute() error: %v", err)
	}
	if state.Observe.FinalContent != "model answer" {
		t.Errorf("FinalContent = %q, want model answer untouched", state.Observe.FinalContent)
	}
}

func TestRunState_BuildResult_ForceFinalReportsLoopKilled(t *testing.T) {
	t.Parallel()
	state := defaultState()
	state.Tool.ForceFinal = true
	if !state.BuildResult().LoopKilled {
		t.Error("LoopKilled = false, want true so team tasks still auto-fail")
	}
}

func TestI18n_LoopStoppedFallback_Translated(t *testing.T) {
	t.Parallel()
	en := i18n.T(i18n.LocaleEN, i18n.MsgLoopStoppedFallback)
	if en == i18n.MsgLoopStoppedFallback {
		t.Fatal("en translation missing")
	}
	for _, locale := range []string{i18n.LocaleVI, i18n.LocaleZH} {
		if got := i18n.T(locale, i18n.MsgLoopStoppedFallback); got == en {
			t.Errorf("locale=%s falls back to English", locale)
		}
	}
}
