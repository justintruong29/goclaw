package tools

import (
	"context"
	"strings"
	"testing"

	"github.com/google/uuid"

	"github.com/nextlevelbuilder/goclaw/internal/store"
	"github.com/nextlevelbuilder/goclaw/internal/vault"
)

// fakeSearchBackend supplies pre-canned results to the VaultSearchService
// via store-shaped fakes (Search service itself is real).

type vsFakeVault struct {
	store.VaultStore
	res []store.VaultSearchResult

	gotOpts store.VaultSearchOptions // captured for assertions on what the tool sent down
}

func (f *vsFakeVault) Search(ctx context.Context, opts store.VaultSearchOptions) ([]store.VaultSearchResult, error) {
	f.gotOpts = opts
	return f.res, nil
}

type vsFakeEpisodic struct {
	store.EpisodicStore
	res []store.EpisodicSearchResult
}

func (f *vsFakeEpisodic) Search(ctx context.Context, query string, agentID, userID string, opts store.EpisodicSearchOptions) ([]store.EpisodicSearchResult, error) {
	return f.res, nil
}

type vsFakeKG struct {
	store.KnowledgeGraphStore
	res []store.Entity
}

func (f *vsFakeKG) SearchEntities(ctx context.Context, agentID, userID, query string, limit int) ([]store.Entity, error) {
	return f.res, nil
}

// TestVaultSearch_ScopeArgIsIgnored pins the fix for the empty-result bug: the
// model used to fill scope="team" from a team-flavoured system prompt, which
// exact-matched vault_documents.scope and dropped every tenant-wide "shared"
// doc, so the tool answered "No results found" on a populated vault. The arg is
// now absent from the schema; a model that sends it anyway must be ignored
// rather than have the search narrowed.
func TestVaultSearch_ScopeArgIsIgnored(t *testing.T) {
	vaultFake := &vsFakeVault{res: []store.VaultSearchResult{
		{Document: store.VaultDocument{ID: "vault-id", Title: "VDoc", Path: "v.md", DocType: "note"}, Score: 0.9, Source: "vault"},
	}}

	tool := NewVaultSearchTool()
	tool.SetSearchService(vault.NewVaultSearchService(vaultFake, nil, nil))

	ctx := store.WithAgentID(store.WithTenantID(context.Background(), uuid.New()), uuid.New())

	res := tool.Execute(ctx, map[string]any{"query": "something", "scope": "team"})
	if res.IsError {
		t.Fatalf("unexpected error: %s", res.ForLLM)
	}
	if got := vaultFake.gotOpts.Scope; got != "" {
		t.Errorf("scope arg must not reach the store, got %q", got)
	}
	if !strings.Contains(res.ForLLM, "doc_id: vault-id") {
		t.Errorf("result dropped despite scope arg: %s", res.ForLLM)
	}
}

// TestVaultSearch_ParametersOmitScope guards the schema itself — leaving the
// param declared would keep inviting the model to send it.
func TestVaultSearch_ParametersOmitScope(t *testing.T) {
	props, ok := NewVaultSearchTool().Parameters()["properties"].(map[string]any)
	if !ok {
		t.Fatal("Parameters()[properties] is not a map")
	}
	if _, exists := props["scope"]; exists {
		t.Error("scope must not be advertised in the tool schema")
	}
	if _, exists := props["query"]; !exists {
		t.Error("query went missing from the tool schema")
	}
}

func TestVaultSearch_OutputIncludesToolHint(t *testing.T) {
	vaultFake := &vsFakeVault{res: []store.VaultSearchResult{
		{Document: store.VaultDocument{ID: "vault-id", Title: "VDoc", Path: "v.md", DocType: "context"}, Score: 0.9, Source: "vault"},
	}}
	epFake := &vsFakeEpisodic{res: []store.EpisodicSearchResult{
		{EpisodicID: "ep-id", SessionKey: "sess", L0Abstract: "abs", Score: 0.7},
	}}
	kgFake := &vsFakeKG{res: []store.Entity{
		{ID: "kg-id", Name: "KGEntity", EntityType: "document", Confidence: 0.6, Description: "desc"},
	}}

	svc := vault.NewVaultSearchService(vaultFake, epFake, kgFake)
	tool := NewVaultSearchTool()
	tool.SetSearchService(svc)

	tenantID := uuid.New()
	agentID := uuid.New()
	ctx := store.WithAgentID(store.WithTenantID(context.Background(), tenantID), agentID)

	res := tool.Execute(ctx, map[string]any{"query": "something"})
	if res.IsError {
		t.Fatalf("unexpected error: %s", res.ForLLM)
	}
	out := res.ForLLM

	// Per-source id field names match each downstream tool's input param —
	// the schema-level fix that prevents LLM from misrouting a foreign id
	// into vault_read.
	if !strings.Contains(out, "doc_id: vault-id") {
		t.Errorf("vault result must use 'doc_id:' field: %s", out)
	}
	if !strings.Contains(out, "entity_id: kg-id") {
		t.Errorf("kg result must use 'entity_id:' field: %s", out)
	}
	if !strings.Contains(out, "episodic_id: ep-id") {
		t.Errorf("episodic result must use 'episodic_id:' field: %s", out)
	}
	// Generic `id:` label must not appear — it is the honeypot that caused
	// the original bug (LLM pattern-matched `id:` regex to doc_id).
	if strings.Contains(out, " id: ") {
		t.Errorf("generic ' id: ' label leaked into output: %s", out)
	}
	// Follow-up tool hint still present per result as secondary signal.
	if !strings.Contains(out, "vault_read") {
		t.Errorf("vault hint missing: %s", out)
	}
	if !strings.Contains(out, "knowledge_graph_search") {
		t.Errorf("kg hint missing: %s", out)
	}
	if !strings.Contains(out, "memory_expand") {
		t.Errorf("episodic hint missing: %s", out)
	}
}
