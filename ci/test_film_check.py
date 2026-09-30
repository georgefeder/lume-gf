"""Tests for film-check.py (unittest; run by the script tests)."""
import os, subprocess, sys, tempfile, unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "film-check.py")


def run(lumas):
    d = tempfile.mkdtemp()
    with open(os.path.join(d, "luma.csv"), "w") as f:
        f.write("frame,seconds,luma\n")
        for i, v in enumerate(lumas):
            f.write("%d,%.3f,%.4f\n" % (i, i / 15, v))
    return subprocess.run([sys.executable, SCRIPT, d], capture_output=True, text=True)


class FilmCheckTests(unittest.TestCase):
    def test_the_light_screen_flashing_dark_before_the_player_is_caught(self):
        # the film of build 8: light list, the list in dark mode, one light frame, then the player
        r = run([0.94] * 10 + [0.09] * 20 + [0.53, 0.15, 0.03] + [0.01] * 10)
        self.assertEqual(r.returncode, 1)
        self.assertIn("flash", r.stdout)

    def test_a_player_sliding_up_over_the_light_screen_is_fine(self):
        r = run([0.94] * 10 + [0.80, 0.62, 0.41, 0.22, 0.08] + [0.01] * 10)
        self.assertEqual(r.returncode, 0)
        self.assertIn("no flash", r.stdout)

    def test_a_film_without_frames_says_so_and_passes(self):
        r = run([])
        self.assertEqual(r.returncode, 0)
        self.assertIn("no frames", r.stdout)


if __name__ == "__main__":
    unittest.main()
