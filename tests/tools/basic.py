import os
import unittest

import parse_cobertura
import testbase


class TooFewArguments(testbase.KcovTestCase):
    def runTest(self):
        self.setUp()
        rv, output = self.do(testbase.kcov + " " + testbase.outbase + "/kcov")

        assert b"Usage: kcov" in output
        assert rv == 1


class WrongArguments(testbase.KcovTestCase):
    def runTest(self):
        self.setUp()
        rv, output = self.do(
            testbase.kcov
            + " --abc=efg "
            + testbase.outbase
            + "/kcov "
            + testbase.testbuild
            + "/tests-stripped"
        )

        assert b"kcov: error: Unrecognized option: --abc=efg" in output
        assert rv == 1


class LookupBinaryInPath(testbase.KcovTestCase):
    @unittest.expectedFailure
    def runTest(self):
        self.setUp()
        os.environ["PATH"] += testbase.sources + "/tests/python"
        noKcovRv, o = self.do(testbase.sources + "/tests/python/main 5")
        rv, o = self.do(testbase.kcov + " " + testbase.outbase + "/kcov " + "main 5")

        dom = parse_cobertura.parseFile(testbase.outbase + "/kcov/main/cobertura.xml")
        assert parse_cobertura.hitsPerLine(dom, "second.py", 34) == 2
        assert noKcovRv, rv


# Issue #414
class OutDirectoryIsExecutable(testbase.KcovTestCase):
    def runTest(self):
        self.setUp()
        # Running a system executable on Linux may cause ptrace to fails with
        # "Operation not permitted", even with ptrace_scope set to 0.
        # See https://www.kernel.org/doc/Documentation/security/Yama.txt
        executable = testbase.sources + "/tests/python/short-test.py"
        rv, o = self.do(testbase.kcov + " echo " + executable)

        assert rv == 0
