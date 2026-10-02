"""Tests for guide-check.py (unittest; run by the script tests). Pixels are made up here; the real ones come from
png-lines.swift on the screenshots."""
import importlib.util, os, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("guide_check", os.path.join(HERE, "guide-check.py"))
gc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gc)

GEOMETRY = ("GFDemo guide geometry: scale=3.0 guideX=0.0 guideY=120.0 guideW=402.0 guideH=754.0 panelMinX=6.0 "
            "panelMaxX=130.0 panelTop=136.0 fade=10.0 room=12.0 rowSpacing=4.0 gone=68.0 clear=130.0")
FOCUSED = "GFDemo focused programme: x=900.0 y=300.0 w=2130.0 h=116.0 scale=1.0056"


class ParsingTests(unittest.TestCase):
    def test_the_last_geometry_line_of_a_log_is_read(self):
        d = tempfile.mkdtemp()
        with open(os.path.join(d, "shot.err"), "w") as f:
            f.write("noise\n" + GEOMETRY.replace("guideY=120.0", "guideY=99.0") + "\nmore noise\n" + GEOMETRY + "\n")
        fields = gc.last_fields(os.path.join(d, "shot.err"), "GFDemo guide geometry:")
        self.assertEqual(fields["guideY"], 120.0)
        self.assertEqual(fields["scale"], 3.0)

    def test_a_log_without_the_line_gives_nothing(self):
        d = tempfile.mkdtemp()
        with open(os.path.join(d, "shot.err"), "w") as f:
            f.write("nothing here\n")
        self.assertIsNone(gc.last_fields(os.path.join(d, "shot.err"), "GFDemo guide geometry:"))
        self.assertIsNone(gc.last_fields(os.path.join(d, "missing.err"), "GFDemo guide geometry:"))


class MeasureTests(unittest.TestCase):
    def test_a_smooth_gradient_has_no_rows_in_it(self):
        self.assertLess(gc.residual([40 + i * 0.02 for i in range(600)]), 0.2)

    def test_rows_of_tiles_do(self):
        rows = ([30] * 20 + [70] * 100) * 5
        self.assertGreater(gc.residual(rows), 5)

    def test_the_first_change_from_the_top_is_found(self):
        self.assertEqual(gc.first_edge([10, 11, 9, 10, 40, 40]), 4)
        self.assertIsNone(gc.first_edge([10, 11, 9, 10]))


class CheckTests(unittest.TestCase):
    def test_background_beside_the_panel_passes(self):
        ok, _ = gc.strip_ok([[0] * 300, [1] * 300])
        self.assertTrue(ok)

    def test_tile_bits_beside_the_panel_fail(self):
        # build 9 on iPhone: up to 191 in the strip left of the panel
        ok, detail = gc.strip_ok([[0] * 100 + [191] * 20 + [0] * 100])
        self.assertFalse(ok)
        self.assertIn("191", detail)

    def test_nothing_left_under_the_panel_passes(self):
        ok, _ = gc.under_ok([[20] * 500, [21] * 500], [([30] * 20 + [70] * 100) * 4])
        self.assertTrue(ok)

    def test_programmes_under_the_panels_left_half_fail(self):
        rows = ([30] * 20 + [70] * 100) * 4
        ok, _ = gc.under_ok([rows], [rows])
        self.assertFalse(ok)

    def test_a_picture_without_programmes_cannot_prove_anything(self):
        ok, detail = gc.under_ok([[20] * 500], [[20] * 500])
        self.assertFalse(ok)
        self.assertIn("no programmes", detail)

    def test_a_first_row_below_the_fade_passes(self):
        ok, _ = gc.first_row_ok([14.0, 14.3, 13.7], fade=10)
        self.assertTrue(ok)

    def test_a_first_row_inside_the_fade_fails(self):
        # build 9 on iPhone: the first tile started 2 points down, inside the 10-point fade
        ok, _ = gc.first_row_ok([4.0, 3.7, 40.0], fade=10)
        self.assertFalse(ok)

    def test_a_first_row_far_below_where_it_belongs_fails(self):
        # the room above the first row added twice would still be "below the fade"
        ok, detail = gc.first_row_ok([28.0, 28.0, 28.0], fade=10, expected=14)
        self.assertFalse(ok)
        self.assertIn("14", detail)

    def test_a_first_row_where_it_belongs_passes(self):
        ok, _ = gc.first_row_ok([14.0, 13.3, 14.7], fade=10, expected=14)
        self.assertTrue(ok)

    def test_no_row_found_fails(self):
        ok, _ = gc.first_row_ok([None, None, None], fade=10)
        self.assertFalse(ok)

    def test_a_focused_long_programme_that_keeps_to_itself_passes(self):
        ok, _ = gc.focus_ok(before=45, inside=225, width=2130)
        self.assertTrue(ok)

    def test_a_focused_long_programme_over_its_neighbour_fails(self):
        # build 9: the white focus glass reached 75 points over the tile before it
        ok, _ = gc.focus_ok(before=220, inside=225, width=2130)
        self.assertFalse(ok)

    def test_the_focus_must_be_on_the_long_programme(self):
        ok, detail = gc.focus_ok(before=45, inside=225, width=300)
        self.assertFalse(ok)
        self.assertIn("long programme", detail)


class PlanTests(unittest.TestCase):
    """Where the lines are drawn, in pixels, from the logged points."""

    def test_strip_lines_run_down_the_iphones_strip_left_of_the_panel(self):
        g = gc.parse_fields(GEOMETRY.split(":", 1)[1])
        lines = gc.strip_lines(g)
        self.assertTrue(lines)
        for x0, y0, x1, y1 in lines:
            self.assertEqual(x0, x1)
            self.assertTrue(0 <= x0 < 18)  # 6 points at 3x
            self.assertGreater(y0, 120 * 3 + 12 * 3)  # below the room above the first row
            self.assertGreater(y1, y0)

    def test_the_apple_tvs_panel_has_no_strip_beside_it(self):
        g = gc.parse_fields(GEOMETRY.split(":", 1)[1].replace("panelMinX=6.0", "panelMinX=0.0"))
        self.assertEqual(gc.strip_lines(g), [])

    def test_under_lines_sit_in_the_panels_left_half_and_the_controls_right_of_it(self):
        g = gc.parse_fields(GEOMETRY.split(":", 1)[1])
        left, control = gc.under_lines(g)
        for x0, _, _, _ in left:
            self.assertTrue(6 * 3 <= x0 <= 68 * 3)
        for x0, _, _, _ in control:
            self.assertGreater(x0, 130 * 3)


class FocusPlanTests(unittest.TestCase):
    def test_the_focus_is_measured_just_left_of_the_tile_and_inside_it_top_to_bottom(self):
        # the tile's text must not decide it (the reviewer: the row centre hit the start time's digits)
        f = gc.parse_fields(FOCUSED.split(":", 1)[1])
        before, inside = gc.focus_lines(f, scale=2.0)
        self.assertEqual(before[0], before[2])
        self.assertEqual(inside[0], inside[2])
        self.assertEqual(before[0], (900 - 3) * 2)
        self.assertEqual(inside[0], (900 + 30) * 2)
        self.assertEqual((before[1], before[3]), ((300 + 7) * 2, (300 + 116 - 7) * 2))
        self.assertEqual((inside[1], inside[3]), ((300 + 10) * 2, (300 + 116 - 10) * 2))


class RowTests(unittest.TestCase):
    LOG = ("GFDemo rail card: 0 310.0 260.0 Recently Added\n"
           "GFDemo rail card: 1 290.0 280.0 Recently Added\n"     # a two-line title, centred: 20 points higher
           "GFDemo rail card: 1 310.0 280.0 Recently Added\n"     # later line wins
           "GFDemo rail card: 0 600.0 200.0 Recently Watched\n"
           "GFDemo rail card: 1 600.0 120.0 Recently Watched\n")

    def write(self, text):
        d = tempfile.mkdtemp()
        path = os.path.join(d, "shot.err")
        with open(path, "w") as f:
            f.write(text)
        return path

    def test_cards_are_read_per_row_with_the_last_position_winning(self):
        rows = gc.rail_cards(self.write(self.LOG))
        self.assertEqual(sorted(rows), ["Recently Added", "Recently Watched"])
        self.assertEqual(rows["Recently Added"][1], 310.0)

    def test_posters_level_at_the_top_pass(self):
        ok, _ = gc.rows_level_ok(gc.rail_cards(self.write(self.LOG)))
        self.assertTrue(ok)

    def test_a_poster_higher_than_its_neighbours_fails(self):
        # Georgs' photo of the Series page (2 Oct): the two-line titles' posters sat higher
        ok, detail = gc.rows_level_ok(gc.rail_cards(self.write(self.LOG + "GFDemo rail card: 2 290.0 280.0 Recently Added\n")))
        self.assertFalse(ok)
        self.assertIn("Recently Added", detail)

    def test_no_rows_logged_fails(self):
        ok, _ = gc.rows_level_ok({})
        self.assertFalse(ok)

    def test_the_top_of_home_shows_recently_watched(self):
        ok, _ = gc.home_rows_ok({"Recently Watched": {0: 1.0}, "Favorites": {0: 1.0}}, gc.HOME_TOP)
        self.assertTrue(ok)

    def test_a_home_without_recently_watched_fails(self):
        ok, detail = gc.home_rows_ok({"Favorites": {0: 1.0}}, gc.HOME_TOP)
        self.assertFalse(ok)
        self.assertIn("Recently Watched", detail)

    def test_home_shows_the_recently_added_rows(self):
        rows = {"Recently Added Movies": {0: 1.0}, "Recently Added Series": {0: 1.0}}
        ok, _ = gc.home_rows_ok(rows, gc.HOME_ADDED)
        self.assertTrue(ok)

    def test_a_home_without_recently_added_fails(self):
        # Georgs' Apple TV (2 Oct): Home showed only the sports row
        ok, detail = gc.home_rows_ok({"Recently Added Movies": {0: 1.0}}, gc.HOME_ADDED)
        self.assertFalse(ok)
        self.assertIn("Recently Added Series", detail)

    def test_each_home_picture_is_checked_for_its_own_rows(self):
        # the rows below the first screen are never drawn (Lume builds Home's rows as they scroll in), so the recently
        # added rows are checked on a Home with Recently Watched and Favorites switched off
        self.assertEqual(gc.HOME_SHOTS["iphone-home-dark"], gc.HOME_TOP)
        self.assertEqual(gc.HOME_SHOTS["tv-home"], gc.HOME_TOP)
        self.assertEqual(gc.HOME_SHOTS["iphone-home-added-dark"], gc.HOME_ADDED)
        self.assertEqual(gc.HOME_SHOTS["tv-home-added"], gc.HOME_ADDED)
        self.assertEqual(gc.HOME_TOP + gc.HOME_ADDED,
                         ("Recently Watched", "Recently Added Movies", "Recently Added Series"))

    def test_the_posters_are_checked_on_every_poster_picture(self):
        for shot in ("iphone-home-dark", "iphone-home-added-dark", "iphone-movies-dark", "iphone-series-dark",
                     "tv-home", "tv-home-added", "tv-movies"):
            self.assertIn(shot, gc.POSTER_SHOTS)


class MainTests(unittest.TestCase):
    def test_a_missing_screen_scale_is_a_failure(self):
        d = tempfile.mkdtemp()
        os.makedirs(os.path.join(d, "logs"))
        with open(os.path.join(d, "logs", "iphone-guide-dark.err"), "w") as f:
            f.write(GEOMETRY.replace("scale=3.0", "scale=0.0") + "\n")
        results = dict((check, (ok, detail)) for check, ok, detail in
                       gc.run_checks(d, sample=lambda png, lines: [[0] * 50 for _ in lines]))
        ok, detail = results["beside the panel (iphone-guide-dark)"]
        self.assertFalse(ok)
        self.assertIn("scale", detail)

    def test_missing_pictures_and_logs_are_failures_not_passes(self):
        d = tempfile.mkdtemp()
        os.makedirs(os.path.join(d, "logs"))
        results = gc.run_checks(d, sample=lambda png, lines: [[] for _ in lines])
        self.assertTrue(results)
        self.assertTrue(all(not ok for _, ok, _ in results))


if __name__ == "__main__":
    unittest.main()
