package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// signIn stands in for the browser sign-in: it leaves a login (and who it is) in the config dir.
func signIn(t *testing.T, email string) func(dir string) error {
	return func(dir string) error {
		writeJSON(t, filepath.Join(dir, ".credentials.json"), map[string]any{"claudeAiOauth": map[string]any{"accessToken": "t-" + email, "expiresAt": float64(4_000_000_000_000)}})
		writeJSON(t, filepath.Join(dir, ".claude.json"), map[string]any{"oauthAccount": map[string]any{"emailAddress": email}})
		return nil
	}
}

func TestAddNamesTheNextFreeAccountAndReportsWhoSignedIn(t *testing.T) {
	home := makeHome(t, map[string]string{"default": "t-default", "account-1": "t-one"})
	a := newAccounts(home, credentialsFile, "")
	var out bytes.Buffer
	if err := addAccount(a, "", signIn(t, "new@example.com"), &out); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "Added account-2 (new@example.com). 3 accounts now.") {
		t.Fatal(out.String())
	}
	if len(freshAccounts(a)) != 3 {
		t.Fatal("the new login is not discovered")
	}
}

func TestAddWarnsWhenTheSameLoginIsAddedTwice(t *testing.T) {
	home := makeHome(t, map[string]string{"default": "t-default"})
	var out bytes.Buffer
	if err := addAccount(newAccounts(home, credentialsFile, ""), "again", signIn(t, "default@example.com"), &out); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "same login") {
		t.Fatal(out.String())
	}
}

func TestAddRefusesBadNamesAndCleansUpAFailedSignIn(t *testing.T) {
	home := t.TempDir()
	a := newAccounts(home, credentialsFile, "")
	for _, name := range []string{"default", "../x", "a b"} {
		if err := addAccount(a, name, signIn(t, "x@example.com"), &bytes.Buffer{}); err == nil {
			t.Fatalf("%q accepted", name)
		}
	}
	failing := func(string) error { return os.ErrPermission }
	if err := addAccount(a, "work", failing, &bytes.Buffer{}); err == nil {
		t.Fatal("failed sign-in reported as added")
	}
	if _, err := os.Stat(filepath.Join(home, ".claude-work")); !os.IsNotExist(err) {
		t.Fatal("empty dir left behind")
	}
	noLogin := func(string) error { return nil }
	if err := addAccount(a, "work", noLogin, &bytes.Buffer{}); err == nil {
		t.Fatal("sign-in without a login reported as added")
	}
}

func TestRemoveDeletesTheLoginAfterConfirmationAndNeverTheDefault(t *testing.T) {
	home := makeHome(t, map[string]string{"default": "t-default", "work": "t-work"})
	a := newAccounts(home, credentialsFile, "")
	var out bytes.Buffer
	if err := removeAccount(a, []string{"work"}, strings.NewReader("n\n"), &out); err != nil {
		t.Fatal(err)
	}
	if len(freshAccounts(a)) != 2 {
		t.Fatal("removed without confirmation")
	}
	if err := removeAccount(a, []string{"default", "-y"}, strings.NewReader(""), &out); err == nil {
		t.Fatal("default removed")
	}
	if err := removeAccount(a, []string{"work"}, strings.NewReader("y\n"), &out); err != nil {
		t.Fatal(err)
	}
	if list := freshAccounts(a); len(list) != 1 || list[0].ID != "default" {
		t.Fatal(list)
	}
}

func TestListMarksTheActiveAccountFromStatus(t *testing.T) {
	raw := []byte(`[{"id":"default","spentUntil":null,"activeFor":[]},{"id":"work","spentUntil":null,"activeFor":["shared"]}]`)
	if activeFromStatus(raw) != "work" {
		t.Fatal("active not read")
	}
}
