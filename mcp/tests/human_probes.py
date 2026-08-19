"""How the server behaves for a stranger who types badly.

WHY THIS EXISTS
---------------
`eval_faq.py` and `script_questions.py` both measure one thing: can the ranker find a
record inside its own corpus when handed a query built from that record. Neither measures
what a human hits first, which is three failures stacked:

  1. TOOL SELECTION - six tools are offered and the human types one sentence. The existing
     evals call `tools.find_script()` directly, so the choice is already made for them.
  2. RETRIEVAL - covered already. Extended here, not re-derived.
  3. WHETHER THE REPLY IS ANY GOOD - rank-1 correct and still useless is a real outcome.

THE ANTI-FAKE PROTOCOL (the part that makes the number worth having)
--------------------------------------------------------------------
* Every expected answer in this file was WRITTEN AND SAVED BEFORE THE TOOL WAS CALLED.
  Ground truth (which scripts/errors/waits exist) was read from the datasets first; no
  probe's reply was read before its `expect` was fixed.
* A probe is NEVER edited after seeing its result. A probe that turns out ambiguous or
  badly written is marked VOID with a reason and excluded from the score. Voiding is
  honest; rewriting is not.
* HALF THE SET IS HOLDOUT and is not read until the end. Same discipline as
  `script_questions.py`.
* RANK-1 IS THE ONLY PASS. "It was in the top 8" is a failure - the human does not give it
  a second try before losing faith.
* OFF-DOMAIN probes score as a FAILURE when answered from recall even if the answer is
  right. That is the server's whole reason to exist.

LAYERS
------
  A (this file, 70 probes)  retrieval, batch, calls tools.* directly. Run it:
                              PYTHONIOENCODING=utf-8 python tests/human_probes.py
                            Misses -> output-files/human-probe-misses-A.txt
  B (35 probes, declared here, run by hand)  tool SELECTION through the live mcp__sqldba__*
                            tools, one sentence at a time, first call graded.
  C (15 probes, rubric here)  reply quality, judged not matched, over replies that PASSED.

MATCH MODES
-----------
  lead_script   first '### Name' in a find_script reply must be in `expect`
  lead_error    the error the reply leads with must be in `expect`
  lead_wait     the wait heading must contain one of `expect`
  contains_all  every string in `expect` must appear (check_build: build identity + train)
  slug_any      the FIRST cited post URL must contain one of `expect`. Used for
                answer_question: the criterion is "the post it cites is about the thing the
                human asked about", which is declarable without seeing the answer.
  refuse        the reply must cleanly say it is not in the library, with no answer attached
"""
from __future__ import annotations

import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / 'src'))

from sqldba_mcp import tools  # noqa: E402

OUT_DIR = pathlib.Path(__file__).resolve().parents[2] / 'output-files'

REFUSALS = (
    'is not in the library yet',
    'Nothing in the dba-tools library matches',
    'Nothing in the published FAQ answers matches',
    'Not in the sqldba.blog library yet',
)


# =========================================================================================
# LAYER A - 70 probes. 35 TUNE / 35 HOLDOUT.
# Sources: MCP-HUMAN-QUESTIONS.md seed, MCP-USAGE-LOG.md real questions,
# output-files/eval-misses-*.txt, and probes written deliberately unlike the author's voice
# (lower case, no punctuation, half a sentence, the wrong noun, a typo in the identifier).
# =========================================================================================

LAYER_A = [

    # --- lookup_error -------------------------------------------------------------------
    dict(id='A01', half='TUNE', tool='lookup_error', mode='lead_error',
         q='what does 18456 mean', expect=[18456]),
    dict(id='A02', half='TUNE', tool='lookup_error', mode='lead_error',
         q='login failed for user, state 38 - is that the password or the database',
         expect=[18456, 4060, 18452],
         note='state 38 is "database not found"; 18456 or 4060 both fair'),
    dict(id='A03', half='TUNE', tool='lookup_error', mode='lead_error',
         q='Msg 9002, Level 17, State 4 - help', expect=[9002]),
    dict(id='A04', half='TUNE', tool='lookup_error', mode='lead_error',
         q='error 701 keeps showing up in the log overnight', expect=[701]),
    dict(id='A05', half='TUNE', tool='lookup_error', mode='lead_error',
         q='is 823 something I need to panic about', expect=[823, 824, 825]),
    dict(id='A06', half='TUNE', tool='lookup_error', mode='refuse',
         q='15247', note='NOT in the 47-error corpus; must say so, not improvise'),
    dict(id='A07', half='TUNE', tool='lookup_error', mode='lead_error',
         q='the transaction log for my database is full', expect=[9002]),

    dict(id='A08', half='HOLDOUT', tool='lookup_error', mode='refuse',
         q='3041 in the error log every night at 2am',
         note='3041 (backup failed) is NOT in the corpus'),
    dict(id='A09', half='HOLDOUT', tool='lookup_error', mode='lead_error',
         q='cannot insert duplicate key row', expect=[2601, 2627]),
    dict(id='A10', half='HOLDOUT', tool='lookup_error', mode='lead_error',
         q='could not allocate space because the filegroup is full', expect=[1105]),
    dict(id='A11', half='HOLDOUT', tool='lookup_error', mode='lead_error',
         q='msg 605 attempt to fetch logical page', expect=[605]),
    dict(id='A12', half='HOLDOUT', tool='lookup_error', mode='lead_error',
         q='string or binary data would be truncated', expect=[8152]),
    dict(id='A13', half='HOLDOUT', tool='lookup_error', mode='lead_error',
         q='deadlock victim', expect=[1205, 1222]),
    dict(id='A14', half='HOLDOUT', tool='lookup_error', mode='slug_any',
         q='the certificate chain was issued by an authority that is not trusted',
         expect=['certificate-chain'],
         note='the one corpus record with error_number None - reachable only by phrase'),

    # --- explain_wait -------------------------------------------------------------------
    dict(id='A15', half='TUNE', tool='explain_wait', mode='lead_wait',
         q='explain PAGEIOLATCH_SH', expect=['PAGEIOLATCH']),
    dict(id='A16', half='TUNE', tool='explain_wait', mode='lead_wait',
         q='cxpacket is 60% of my waits, do I care', expect=['CXPACKET', 'CXCONSUMER']),
    dict(id='A17', half='TUNE', tool='explain_wait', mode='lead_wait',
         q='what is asyncnetworkio', expect=['ASYNC_NETWORK_IO'],
         note='deliberate sloppy spelling - underscores dropped'),
    dict(id='A18', half='TUNE', tool='explain_wait', mode='lead_wait',
         q='top wait is WRITELOG, is that the disk or the app', expect=['WRITELOG']),
    dict(id='A19', half='TUNE', tool='explain_wait', mode='lead_wait',
         q='is THREADPOOL bad', expect=['THREADPOOL']),
    dict(id='A20', half='TUNE', tool='explain_wait', mode='lead_wait',
         q='resource_semaphore - memory grants?', expect=['RESOURCE_SEMAPHORE']),
    dict(id='A21', half='TUNE', tool='explain_wait', mode='lead_wait',
         q='SOS_SCHEDULER_YIELD high, does that mean I need more CPU',
         expect=['SOS_SCHEDULER_YIELD']),

    dict(id='A22', half='HOLDOUT', tool='explain_wait', mode='lead_wait',
         q='LCK_M_X', expect=['LCK_M_X', 'LCK_M']),
    dict(id='A23', half='HOLDOUT', tool='explain_wait', mode='lead_wait',
         q='pageiolatch_sh', expect=['PAGEIOLATCH'], note='lower case, as typed'),
    dict(id='A24', half='HOLDOUT', tool='explain_wait', mode='lead_wait',
         q='PAGEIOLATCH', expect=['PAGEIOLATCH'],
         note='truncated identifier - no suffix. Any PAGEIOLATCH_* family reply is fair'),
    dict(id='A25', half='HOLDOUT', tool='explain_wait', mode='lead_wait',
         q='hadr_sync_commit', expect=['HADR_SYNC_COMMIT']),
    dict(id='A26', half='HOLDOUT', tool='explain_wait', mode='lead_wait',
         q='whats the difference between CXCONSUMER and CXPACKET',
         expect=['CXPACKET', 'CXCONSUMER']),
    dict(id='A27', half='HOLDOUT', tool='explain_wait', mode='lead_wait',
         q='PAGELATCH_UP on tempdb', expect=['PAGELATCH']),
    dict(id='A28', half='HOLDOUT', tool='explain_wait', mode='refuse',
         q='FOO_BAR_WAIT', note='invented wait type - must not be explained'),

    # --- check_build --------------------------------------------------------------------
    dict(id='A29', half='TUNE', tool='check_build', mode='contains_all',
         q="I'm on 16.0.4165.4, is that patched", expect=['2022']),
    dict(id='A30', half='TUNE', tool='check_build', mode='contains_all',
         q='how many CUs behind is 15.0.4280.7', expect=['2019', 'behind']),
    dict(id='A31', half='TUNE', tool='check_build', mode='contains_all',
         q='what CU is 16.0.4135.4', expect=['2022', 'CU']),
    dict(id='A32', half='TUNE', tool='check_build', mode='contains_all',
         q='13.0.5426.0', expect=['2016', 'CU8'],
         note='the 0.3.0 acceptance build - must IDENTIFY, not just judge'),
    dict(id='A33', half='TUNE', tool='check_build', mode='contains_all',
         q='when does SQL 2017 go out of support', expect=['2017'],
         note='no build number in the question at all - can check_build cope?'),
    dict(id='A34', half='TUNE', tool='check_build', mode='refuse',
         q='10.50.4000.0', note='SQL 2008 R2 - known absent, must say not in the library'),

    dict(id='A35', half='HOLDOUT', tool='check_build', mode='contains_all',
         q='@@VERSION says Microsoft SQL Server 2019 (RTM-CU18) am I behind', expect=['2019']),
    dict(id='A36', half='HOLDOUT', tool='check_build', mode='contains_all',
         q='14.0.3445.2', expect=['2017']),
    dict(id='A37', half='HOLDOUT', tool='check_build', mode='contains_all',
         q='12.0.6024.0', expect=['2014']),
    dict(id='A38', half='HOLDOUT', tool='check_build', mode='contains_all',
         q='11.0.7001.0', expect=['2012']),
    dict(id='A39', half='HOLDOUT', tool='check_build', mode='contains_all',
         q='17.0.4075.5', expect=['2025']),
    dict(id='A40', half='HOLDOUT', tool='check_build', mode='refuse',
         q='9.00.5000.00', note='SQL 2005 - known absent'),

    # --- find_script --------------------------------------------------------------------
    dict(id='A41', half='TUNE', tool='find_script', mode='lead_script',
         q='find blocking chains', expect=['Get-BlockingChains', 'Get-BlockingSessions',
                                           'Get-BlockingChainsWithPlan']),
    dict(id='A42', half='TUNE', tool='find_script', mode='lead_script',
         q='show me who has sysadmin', expect=['Get-SysadminMembers', 'Get-ServerRoleMembers'],
         note='usage-log row 2: previously led with Get-RecentErrorLogEntries'),
    dict(id='A43', half='TUNE', tool='find_script', mode='lead_script',
         q='something to check my backups are actually running',
         expect=['Get-BackupCoverage', 'Get-LastDatabaseBackupTimes', 'Get-BackupAge']),
    dict(id='A44', half='TUNE', tool='find_script', mode='lead_script',
         q='script for index fragmentation',
         expect=['Get-IndexFragmentation', 'Get-IndexFragmentationAcrossDatabases']),
    dict(id='A45', half='TUNE', tool='find_script', mode='lead_script',
         q='do you have anything for finding unused indexes',
         expect=['Get-UnusedIndexes', 'Get-IndexUsageStats']),
    dict(id='A46', half='TUNE', tool='find_script', mode='lead_script',
         q="I need to see what's running right now",
         expect=['Get-ActiveRequests', 'Get-ActiveSessions', 'Get-LongRunningQueries',
                 'Get-ActiveRequestsWithPlan']),
    dict(id='A47', half='TUNE', tool='find_script', mode='lead_script',
         q='give me something to check TempDB config',
         expect=['Get-TempDbConfiguration', 'Get-TempDbFileBalance']),
    dict(id='A48', half='TUNE', tool='find_script', mode='lead_script',
         q='anything that dumps out all the logins and their permissions',
         expect=['Get-LoginPermissions', 'Get-UserPermissionsAudit', 'Get-DatabasePermissions',
                 'Get-LoginInventory']),
    dict(id='A49', half='TUNE', tool='find_script', mode='lead_script',
         q='what have you got for slow queries',
         expect=['Get-LongRunningQueries', 'Get-SlowQueriesFromCache', 'Get-TopCpuQueries',
                 'Get-QueryStoreTopQueries']),
    dict(id='A50', half='TUNE', tool='find_script', mode='lead_script',
         q='which scripts check backups',
         expect=['Get-BackupCoverage', 'Get-LastDatabaseBackupTimes', 'Get-BackupAge',
                 'Get-BackupChainIntegrity'],
         note='usage-log row 7: previously led with Get-LastRestoreHistory'),

    dict(id='A51', half='HOLDOUT', tool='find_script', mode='lead_script',
         q='backups', expect=['Get-BackupCoverage', 'Get-LastDatabaseBackupTimes',
                              'Get-BackupAge', 'Get-DatabaseBackupHistory',
                              'Get-BackupChainIntegrity'],
         note='one word, no sentence'),
    dict(id='A52', half='HOLDOUT', tool='find_script', mode='lead_script',
         q='who can do anything on this box',
         expect=['Get-SysadminMembers', 'Get-ServerRoleMembers', 'Get-LoginPermissions'],
         note='the wrong noun - no keyword overlap with the script name at all'),
    dict(id='A53', half='HOLDOUT', tool='find_script', mode='lead_script',
         q='i need to know if my log backups are broken',
         expect=['Get-BackupChainIntegrity', 'Get-BackupCoverage']),
    dict(id='A54', half='HOLDOUT', tool='find_script', mode='lead_script',
         q='wheres my free space',
         expect=['Get-DiskSpace', 'Get-DiskSpaceSummary', 'Get-DatabaseFreeSpaceSummary',
                 'Get-DatabaseSizesAndFreeSpace', 'Get-FilegroupSpace']),
    dict(id='A55', half='HOLDOUT', tool='find_script', mode='lead_script',
         q='job failed last night what happened',
         expect=['Get-SqlAgentJobFailureSummary', 'Get-SqlAgentJobOverview']),
    dict(id='A56', half='HOLDOUT', tool='find_script', mode='lead_script',
         q='vlfs', expect=['Get-VlfCount']),
    dict(id='A57', half='HOLDOUT', tool='find_script', mode='lead_script',
         q='checkdb last run', expect=['Get-LastDbccCheckdb', 'Get-DatabaseIntegrityChecks']),
    dict(id='A58', half='HOLDOUT', tool='find_script', mode='lead_script',
         q='how big are my tables', expect=['Get-TableSizes', 'Get-DatabaseSizesAndFreeSpace']),
    dict(id='A59', half='HOLDOUT', tool='find_script', mode='lead_script',
         q='is replication falling behind',
         expect=['Get-UndistributedCommands', 'Get-DistributionAgentStatus',
                 'Get-ReplicationStatus', 'Get-LogReaderAgentStatus']),
    dict(id='A60', half='HOLDOUT', tool='find_script', mode='lead_script',
         q='memory pressure', expect=['Get-MemoryConfigurationAndUsage', 'Get-MemoryGrantSpills',
                                      'Get-PlanCacheHealth']),

    # --- answer_question ----------------------------------------------------------------
    # slug_any: the FIRST cited post must be ABOUT the thing asked. Declarable in advance.
    dict(id='A61', half='TUNE', tool='answer_question', mode='slug_any',
         q='should I add a second data file to TempDB', expect=['tempdb', 'temp-db']),
    dict(id='A62', half='TUNE', tool='answer_question', mode='slug_any',
         q='how many TempDB files do I actually need', expect=['tempdb', 'temp-db']),
    dict(id='A63', half='TUNE', tool='answer_question', mode='slug_any',
         q='is shrinking a database ever OK', expect=['shrink']),
    dict(id='A64', half='TUNE', tool='answer_question', mode='slug_any',
         q='what MAXDOP should I set', expect=['maxdop', 'parallel']),
    dict(id='A65', half='TUNE', tool='answer_question', mode='slug_any',
         q='how often should I be rebuilding indexes',
         expect=['index', 'fragmentation', 'maintenance']),

    dict(id='A66', half='HOLDOUT', tool='answer_question', mode='slug_any',
         q='whats a sensible cost threshold for parallelism',
         expect=['parallel', 'cost-threshold', 'maxdop', 'cxpacket']),
    dict(id='A67', half='HOLDOUT', tool='answer_question', mode='slug_any',
         q='do i need to update stats if i rebuild indexes',
         expect=['statistic', 'index']),
    dict(id='A68', half='HOLDOUT', tool='answer_question', mode='slug_any',
         q='simple or full recovery which one',
         expect=['recovery-model', 'recovery', 'log']),
    dict(id='A69', half='HOLDOUT', tool='answer_question', mode='refuse',
         q="what's the connection string format for EF Core",
         note='OFF-DOMAIN. Improvising from recall is a failure even if the answer is right'),
    dict(id='A70', half='HOLDOUT', tool='answer_question', mode='refuse',
         q='best way to move a database to Azure',
         note='OFF-DOMAIN'),
]


# =========================================================================================
# LAYER B - 35 probes, TOOL SELECTION. Run BY HAND through the live mcp__sqldba__* tools,
# one sentence at a time, FIRST CALL GRADED. Declared here before any of them was run.
#
# `want` is the tool that should fire. `also_fair` lists tools that are a defensible pick.
# `must` is what the reply has to do for the probe to pass beyond the routing.
# =========================================================================================

LAYER_B = [
    # -- names the wrong tool in the question itself
    dict(id='B01', half='TUNE', q='explain 9002', want='lookup_error', also_fair=[],
         must='identify error 9002 (log full). "explain" must not route it to explain_wait'),
    dict(id='B02', half='TUNE', q='check build for PAGEIOLATCH_SH', want='explain_wait',
         also_fair=['none'],
         must='mixed nonsense signals - must not confidently produce a build verdict'),
    dict(id='B03', half='TUNE', q='explain 18456', want='lookup_error', also_fair=[],
         must='error, not a wait'),
    dict(id='B04', half='TUNE', q='look up the wait for error 1205', want='lookup_error',
         also_fair=['explain_wait'],
         must='1205 is a deadlock ERROR; LCK_M_* is the wait. Either is defensible'),

    # -- sits between two tools
    dict(id='B05', half='TUNE', q='how do I fix PAGEIOLATCH', want='explain_wait',
         also_fair=['answer_question'], must='silence is not an acceptable outcome'),
    dict(id='B06', half='TUNE', q='should I worry about CXPACKET', want='explain_wait',
         also_fair=['answer_question'], must='must give a verdict'),
    dict(id='B07', half='TUNE', q='my log file keeps growing what do I do',
         want='answer_question', also_fair=['find_script', 'lookup_error'],
         must='any of the three is fair; must not be silent'),
    dict(id='B08', half='TUNE', q='tempdb is full', want='answer_question',
         also_fair=['find_script', 'lookup_error'], must='must land on tempdb, not generic space'),

    # -- bare fragments, no sentence
    dict(id='B09', half='TUNE', q='18456', want='lookup_error', also_fair=[]),
    dict(id='B10', half='TUNE', q='WRITELOG', want='explain_wait', also_fair=[]),
    dict(id='B11', half='TUNE', q='15.0.4280.7', want='check_build', also_fair=[]),
    dict(id='B12', half='TUNE', q='Get-BlockingChains', want='get_script',
         also_fair=['find_script'], must='an exact script name should fetch the script'),
    dict(id='B13', half='TUNE', q='CXPACKET 47%', want='explain_wait', also_fair=[]),

    # -- polite human framing round a good question (the filler IS the test)
    dict(id='B14', half='TUNE', q='hey quick one, can you find me a script that shows most '
         'recent backups', want='find_script', also_fair=[],
         must='must lead with Get-LastDatabaseBackupTimes or Get-BackupAge, not restore history'),
    dict(id='B15', half='TUNE', q='sorry to bother you, what does error 9002 actually mean in '
         'practice', want='lookup_error', also_fair=[]),
    dict(id='B16', half='TUNE', q='ok so i have been asked to check whether this server is '
         'patched, its on 16.0.4165.4', want='check_build', also_fair=[]),

    # -- no tool cleanly owns it
    dict(id='B17', half='TUNE', q='the server is slow', want='none',
         also_fair=['find_script', 'answer_question'],
         must='honest outcome is the health-triage prompt or a redirect, NOT whatever '
              'scored highest'),
    dict(id='B18', half='TUNE', q='is my sql server ok', want='none',
         also_fair=['find_script'], must='triage prompt or redirect'),

    # -- HOLDOUT half
    dict(id='B19', half='HOLDOUT', q='what should I look at first on a server I have never seen',
         want='none', also_fair=['find_script', 'answer_question'],
         must='the sql-server-health-triage prompt is the honest answer'),
    dict(id='B20', half='HOLDOUT', q='give me a list of the top 10 most useful scripts',
         want='none', also_fair=['find_script'],
         must='honest redirect to the hub. A confident wrong list is the failure'),
    dict(id='B21', half='HOLDOUT', q='9002', want='lookup_error', also_fair=[]),
    dict(id='B22', half='HOLDOUT', q='THREADPOOL', want='explain_wait', also_fair=[]),
    dict(id='B23', half='HOLDOUT', q='13.0.5426.0', want='check_build', also_fair=[]),
    dict(id='B24', half='HOLDOUT', q='can i see the actual code before i run it for the '
         'sysadmin one', want='get_script', also_fair=['find_script'],
         must='must resolve "the sysadmin one" to Get-SysadminMembers'),
    dict(id='B25', half='HOLDOUT', q='is that script safe to run on prod',
         want='get_script', also_fair=['find_script', 'none'],
         must='no antecedent - the honest reply asks which script, or states the safety '
              'classes exist. Guessing a script is the failure'),
    dict(id='B26', half='HOLDOUT', q='whats eating my cpu', want='find_script',
         also_fair=['explain_wait', 'answer_question'],
         must='Get-TopCpuQueries family'),
    dict(id='B27', half='HOLDOUT', q='pageiolatch_sh is my top wait and the disks are ssd so '
         'i dont get it', want='explain_wait', also_fair=['answer_question']),
    dict(id='B28', half='HOLDOUT', q='we are on sql 2016, when do we lose support',
         want='check_build', also_fair=['answer_question'],
         must='2016 extended support ended 2026-07-14 - must not be vague'),
    dict(id='B29', half='HOLDOUT', q='someone dropped a table can i get it back',
         want='answer_question', also_fair=['find_script', 'none'],
         must='restore/point-in-time. If nothing is published, say so'),

    # -- off-domain. Honest "not in the library" is the ONLY pass.
    dict(id='B30', half='HOLDOUT', q='how do I set up replication', want='refuse',
         also_fair=[], must='OFF-DOMAIN for setup. Monitoring scripts exist; a how-to does '
                            'not. Improvising a setup guide is the failure'),
    dict(id='B31', half='HOLDOUT', q='best way to move a database to Azure', want='refuse',
         also_fair=[], must='OFF-DOMAIN'),
    dict(id='B32', half='HOLDOUT', q="what's the connection string format for EF Core",
         want='refuse', also_fair=[], must='OFF-DOMAIN'),
    dict(id='B33', half='HOLDOUT', q='how do I install postgres', want='refuse',
         also_fair=[], must='OFF-DOMAIN, different product entirely'),
    dict(id='B34', half='HOLDOUT', q='write me a query to pivot rows into columns',
         want='refuse', also_fair=[], must='OFF-DOMAIN - T-SQL authoring is not this library'),
    dict(id='B35', half='HOLDOUT', q='what is the best sql server book', want='refuse',
         also_fair=[], must='OFF-DOMAIN opinion question'),
]


# =========================================================================================
# LAYER C - reply QUALITY rubric. Fixed in writing before any reply was judged.
# Applied to 15 replies that already PASSED layer A or B, so quality is measured
# independently of correctness.
# =========================================================================================

LAYER_C_RUBRIC = [
    ('C-LEAD',   'Does it answer in the first two lines, or must the human read eight '
                 'candidates first?'),
    ('C-CITE',   'Is there a source URL? The README promises one on EVERY answer - verify, '
                 'do not assume.'),
    ('C-BUILD',  'check_build only: does it state what the build IS, how far behind, and the '
                 'KB to install - and volunteer a freshness warning when the stamp is old?'),
    ('C-SAFETY', 'find_script only: is the SAFE/IMPACT class present, and does anything NOT '
                 'read-only LEAD with the warning? 6 of 183 are not read-only and one created '
                 '30 databases when a sweep guessed from the name. Highest-consequence check.'),
    ('C-REFUSE', 'On a "not in the library" reply: does it say so cleanly, or hedge its way '
                 'into a guess?'),
]


# =========================================================================================
# RUNNER (Layer A only - B and C are run by hand)
# =========================================================================================

def _ascii(s: str) -> str:
    return ''.join(c for c in s if ord(c) < 128)


def _call(p) -> str:
    fn = getattr(tools, p['tool'])
    arg = p['q']
    return fn(arg)


def _is_refusal(reply: str) -> bool:
    return any(r in reply for r in REFUSALS)


def _lead_script(reply: str) -> str | None:
    m = re.search(r'^### (.+)$', reply, re.M)
    return m.group(1).strip() if m else None


def _lead_error(reply: str):
    m = re.search(r'^## Error (\d+)', reply, re.M)
    if m:
        return int(m.group(1))
    m = re.search(r'^- \*\*(\d+)\*\*', reply, re.M)
    if m:
        return int(m.group(1))
    return None


def _lead_wait(reply: str) -> str | None:
    m = re.search(r'^## (.+)$', reply, re.M)
    return m.group(1).strip() if m else None


def _first_url(reply: str) -> str | None:
    m = re.search(r'https://sqldba\.blog/(\S*)', reply)
    return m.group(1) if m else None


def score(p, reply: str):
    """Return (passed: bool, got: str)."""
    mode = p['mode']
    if mode == 'refuse':
        return _is_refusal(reply), 'REFUSED' if _is_refusal(reply) else _ascii(reply[:90])
    if _is_refusal(reply):
        return False, 'REFUSED (expected an answer)'
    if mode == 'lead_script':
        got = _lead_script(reply)
        return (got in p['expect']), got or '(nothing)'
    if mode == 'lead_error':
        got = _lead_error(reply)
        return (got in p['expect']), str(got)
    if mode == 'lead_wait':
        got = _lead_wait(reply) or ''
        return any(e in got for e in p['expect']), got or '(nothing)'
    if mode == 'contains_all':
        missing = [e for e in p['expect'] if e.lower() not in reply.lower()]
        return (not missing), ('OK' if not missing else 'missing ' + ','.join(missing))
    if mode == 'slug_any':
        got = _first_url(reply) or ''
        return any(e in got.lower() for e in p['expect']), got or '(no url)'
    raise ValueError('unknown mode ' + mode)


def main() -> int:
    rows = []
    for p in LAYER_A:
        try:
            reply = _call(p)
        except Exception as exc:                                  # noqa: BLE001
            reply = 'EXCEPTION: %s' % exc
        ok, got = score(p, reply)
        rows.append((p, ok, got, reply))

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / 'human-probe-misses-A.txt'
    misses = [r for r in rows if not r[1]]
    with out.open('w', encoding='utf-8') as fh:
        fh.write('%d misses of %d (layer A, human probes)\n\n' % (len(misses), len(rows)))
        for p, ok, got, reply in misses:
            fh.write('[%s %s %s] %s\n' % (p['id'], p['half'], p['tool'], p['q']))
            fh.write('  want: %s\n' % (p.get('expect') or p['mode']))
            fh.write('  got : %s\n' % got)
            if p.get('note'):
                fh.write('  note: %s\n' % p['note'])
            fh.write('  reply head: %s\n\n' % _ascii(reply[:200]).replace('\n', ' | '))

    print('LAYER A - human probes')
    print('=' * 66)
    print('%-6s %-8s %-16s %-5s %s' % ('id', 'half', 'tool', 'pass', 'got'))
    print('-' * 66)
    for p, ok, got, _ in rows:
        print('%-6s %-8s %-16s %-5s %s'
              % (p['id'], p['half'], p['tool'], 'OK' if ok else 'MISS', _ascii(str(got))[:34]))
    print('-' * 66)
    for half in ('TUNE', 'HOLDOUT'):
        sub = [r for r in rows if r[0]['half'] == half]
        n = len(sub)
        hit = sum(1 for r in sub if r[1])
        print('%-8s rank-1: %3d/%3d  %5.1f%%' % (half, hit, n, 100.0 * hit / n))
    n = len(rows)
    hit = sum(1 for r in rows if r[1])
    print('%-8s rank-1: %3d/%3d  %5.1f%%' % ('ALL', hit, n, 100.0 * hit / n))
    print('\nby tool:')
    for t in ('lookup_error', 'explain_wait', 'check_build', 'find_script', 'answer_question'):
        sub = [r for r in rows if r[0]['tool'] == t]
        if sub:
            hit = sum(1 for r in sub if r[1])
            print('  %-16s %2d/%2d  %5.1f%%' % (t, hit, len(sub), 100.0 * hit / len(sub)))
    print('\nmisses -> %s' % out)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
