import uuid
import unittest

from ..models import Severity
from ..models import Vulnerability
from ..assessor import VulnerabilitiesRiskAssessor
from ..models import Whitelist


class VulnerabilitiesRiskAssessorTestCase(unittest.TestCase):

    def test_ctr(self):
        whitelist = uuid.uuid4().hex
        vulnerabilities = uuid.uuid4().hex

        vra = VulnerabilitiesRiskAssessor(whitelist, vulnerabilities)

        self.assertEqual(whitelist, vra.whitelist)
        self.assertEqual(vulnerabilities, vra.vulnerabilities)

    def test_no_vulnerabilities_should_assess_clean(self):
        for severity in ['Negligible', 'Low', 'Medium', 'High']:
            whitelist = Whitelist('{"ignoreSevertiesAtOrBelow": "%s"}' % severity, [])
            vulnerabilities = []

            vra = VulnerabilitiesRiskAssessor(whitelist, vulnerabilities)
            self.assertTrue(vra.assess())

    def test_X_sev_vul_with_X_sev_wl_should_assess_clean(self):
        for severity in ['Negligible', 'Low', 'Medium', 'High']:
            whitelist = Whitelist(Severity(severity), [])
            vulnerabilities = [
                Vulnerability('CVE-0000-0000', Severity(severity)),
            ]

            vra = VulnerabilitiesRiskAssessor(whitelist, vulnerabilities)
            self.assertTrue(vra.assess())

    def test_high_sev_vul_with_med_sev_wl_should_assess_dirty(self):
        whitelist = Whitelist(Severity('medium'), [])

        vulnerabilities = [
            Vulnerability('CVE-0000-0000', Severity('High')),
        ]

        vra = VulnerabilitiesRiskAssessor(whitelist, vulnerabilities)
        self.assertFalse(vra.assess())
