"""The servicing ladder: every published build, not just the newest one.

`check_build` used to be able to COMPARE a build but never IDENTIFY one - a DBA pasting
13.0.5426.0 was told it was behind, but not that it was CU8 from July 2019. The gap
mattered because an unidentified build is exactly where a model stops looking things up
and starts filling in from memory, and a confidently wrong CU number is worse than saying
nothing.

The two tests worth reading here are the last two. Everything else is shape-checking.
"""
from __future__ import annotations

import unittest

from sqldba_mcp import data, tools

VERIFIED_FIELDS = ('rtm', 'latest_cu', 'latest_cu_gdr', 'latest_gdr', 'latest_sp')


class TestLadderShape(unittest.TestCase):
    def test_every_version_has_a_ladder(self):
        for v in data.builds()['versions']:
            with self.subTest(v['name']):
                self.assertGreaterEqual(len(data.ladder(v)), 15,
                                        '%s ladder looks truncated' % v['name'])

    def test_every_entry_is_dated_and_typed(self):
        allowed = {'CU', 'GDR', 'SP', 'RTM', 'ACP'}
        for v in data.builds()['versions']:
            for u in data.ladder(v):
                with self.subTest(v['name'], build=u['build']):
                    self.assertTrue(data.parse_build(u['build']))
                    self.assertTrue(u.get('date'), 'undated build ships as unciteable')
                    self.assertIn(u.get('train'), allowed)

    def test_ladder_is_newest_first(self):
        for v in data.builds()['versions']:
            got = [data.parse_build(u['build']) for u in data.ladder(v)]
            with self.subTest(v['name']):
                self.assertEqual(got, sorted(got, reverse=True))

    def test_builds_belong_to_their_own_version(self):
        for v in data.builds()['versions']:
            for u in data.ladder(v):
                with self.subTest(v['name'], build=u['build']):
                    self.assertEqual(data.parse_build(u['build'])[0], v['engine_version'])


class TestLadderAgreesWithTheVerifiedSummaries(unittest.TestCase):
    """The ladder is parsed from Microsoft's tables; the latest_* fields are hand-verified.

    Two sources for the same fact is a liability unless something checks they agree. All
    29 of the verified builds reconciled against the harvest when the ladder was first
    built - this keeps it that way, and will fail if a future re-harvest silently drops
    or renumbers a train.
    """

    def test_every_verified_build_appears_in_the_ladder(self):
        for v in data.builds()['versions']:
            builds = {u['build'] for u in data.ladder(v)}
            for f in VERIFIED_FIELDS:
                want = (v.get(f) or {}).get('build')
                if not want:
                    continue
                with self.subTest(v['name'], field=f):
                    self.assertIn(want, builds,
                                  'verified %s %s is missing from the ladder' % (f, want))

    def test_the_latest_cu_is_the_highest_cu_on_the_ladder(self):
        """The Azure Connect Pack trap, kept shut.

        On 2016 and 2017 the Azure Connect Pack sits on a HIGHER build number than the
        final CU (13.0.7000.253 against SP2 CU17's 13.0.5888.11) while being a different
        servicing line entirely. Classifying it as a CU made it outrank the real final CU,
        which would have told a DBA on the CU train they were ~1100 builds behind on a
        train they are not on. It was caught by cross-checking against the hand-verified
        values, not by any test - so this is that check, made permanent.
        """
        for v in data.builds()['versions']:
            want = (v.get('latest_cu') or {}).get('build')
            if not want:
                continue
            cus = [u for u in data.ladder(v) if u['train'] == 'CU']
            if not cus:
                continue
            with self.subTest(v['name']):
                self.assertEqual(cus[0]['build'], want,
                                 'highest CU on the ladder disagrees with the verified '
                                 'latest_cu - check for a non-CU line misclassified as CU')


class TestIdentification(unittest.TestCase):
    def test_a_legacy_build_is_named_not_just_judged(self):
        out = tools.check_build('13.0.5426.0')
        self.assertIn('This build is:', out)
        self.assertIn('CU8', out)
        self.assertIn('2019-07-31', out)
        self.assertIn('BEHIND', out)

    def test_how_far_behind_is_counted_from_published_data(self):
        out = tools.check_build('13.0.5426.0')
        self.assertRegex(out, r'\*\*\d+ CU update\(s\) behind\*\*')

    def test_an_unpublished_build_is_bracketed_rather_than_invented(self):
        """A build Microsoft never shipped publicly is usually an on-demand hotfix.

        Saying "not found" throws away what IS known - which two published builds it sits
        between - and inviting the model to explain the gap itself is how a hotfix number
        turns into a hallucinated CU.
        """
        out = tools.check_build('16.0.4260.1')
        self.assertIn('not one Microsoft published publicly', out)
        self.assertIn('16.0.4255.1', out)
        self.assertNotIn('This build is:', out)

    def test_identification_does_not_fabricate_a_count(self):
        """No "N updates behind" unless the build was identified exactly.

        The count is only meaningful once the train is known. On an unrecognised build the
        train is an assumption, and a specific number attached to an assumption reads as
        far more certain than it is.
        """
        out = tools.check_build('16.0.4260.1')
        self.assertNotRegex(out, r'update\(s\) behind')


if __name__ == '__main__':
    unittest.main()
