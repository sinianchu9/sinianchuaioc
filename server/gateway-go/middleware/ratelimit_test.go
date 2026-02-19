package middleware

import "testing"

func TestCompareSemver(t *testing.T) {
	tests := []struct {
		a, b string
		want int
	}{
		{"1.10.0", "1.2.0", 1},
		{"1.2.0", "1.10.0", -1},
		{"1.2.0", "1.2.0", 0},
		{"2.0.0", "1.99.99", 1},
		{"1.2", "1.2.0", 0},
		{"bad", "1.0.0", -1},
	}

	for _, tt := range tests {
		got := compareSemver(tt.a, tt.b)
		if got < 0 {
			got = -1
		} else if got > 0 {
			got = 1
		}
		if got != tt.want {
			t.Fatalf("compareSemver(%q, %q)=%d, want %d", tt.a, tt.b, got, tt.want)
		}
	}
}
