"""How a DBA asks for a script at 2am, paired with the script they mean.

`find_script` is the tool most likely to be called first and it shipped with no published
number at all, while the FAQ, error and wait suites each had one. Measured for the first
time it scored 37.2% top-1: "what is blocking right now" did not return `Get-BlockingChains`
and "is my database corrupt" returned nothing whatsoever.

TWO HALVES, AND THE SPLIT IS THE POINT
--------------------------------------
`TUNE` is what may be looked at while changing the ranker. `HOLDOUT` is not, and it is not
reported on until the work is finished. A score from the half that was tuned on is not
evidence, it is a memory test - and every probe set an author writes drifts toward the
phrasings that already work unless something stops it.

Peter's own ten questions are in TUNE, because he had already run them and their results
were already known when this file was written. Nothing learned from them is held back.

The HOLDOUT half is deliberately written the way someone types under pressure: lower case,
filler words, half a sentence, the wrong noun. If every probe reads like a script title,
the set is measuring whether the index can match a title, which is not the problem.

RANK-1 IS THE ONLY PASS. Recall@8 is what the tool already achieved; being somewhere in a
list of eight is not the same as being the answer. Where more than one script genuinely
answers the question all fair answers are listed and any of them counts as rank-1.
"""

# --- TUNE: may be inspected and tuned against -------------------------------------------
# The first ten are Peter's, verbatim, with the result he saw noted where it was wrong.
TUNE = [
    ("sysadmin members",                              ["Get-SysadminMembers"]),
    ("show me who has sysadmin",                       ["Get-SysadminMembers"]),
    ("give a script to show sysadmins",                ["Get-SysadminMembers"]),
    ("most recent backups",                            ["Get-LastDatabaseBackupTimes"]),
    ("backup scripts",                                 ["Get-BackupCoverage",
                                                        "Get-LastDatabaseBackupTimes"]),
    ("which scripts check backups",                    ["Get-BackupCoverage",
                                                        "Get-LastDatabaseBackupTimes"]),
    ("give a script to show user permissions",         ["Get-LoginPermissions",
                                                        "Get-UserPermissionsAudit",
                                                        "Get-DatabasePermissions"]),
    ("give me a script for showing most recent backups", ["Get-LastDatabaseBackupTimes"]),
    # --- ordinary phrasings, same shape
    ("show me the missing indexes",                    ["Get-MissingIndexes"]),
    ("give me a script to find blocking",              ["Get-BlockingChains",
                                                        "Get-BlockingSessions"]),
    ("i need a script that shows disk space",          ["Get-DiskSpace",
                                                        "Get-DiskSpaceSummary"]),
    ("script to check tempdb",                         ["Get-TempDbConfiguration",
                                                        "Get-TempDbFileBalance",
                                                        "Get-TempdbUsage"]),
    ("how do I see the error log",                     ["Get-RecentErrorLogEntries"]),
    ("what version is this server on",                 ["Get-VersionAndEdition"]),
    ("last time checkdb ran",                          ["Get-LastDbccCheckdb"]),
    ("current wait stats",                             ["Get-WaitStatistics"]),
    ("failed agent jobs",                              ["Get-SqlAgentJobFailureSummary"]),
    ("orphaned users",                                 ["Get-OrphanedUsers"]),
    ("show me long running queries",                   ["Get-LongRunningQueries",
                                                        "Get-ActiveRequests"]),
    ("vlf count",                                      ["Get-VlfCount"]),
    ("latest full backup for each database",           ["Get-LastDatabaseBackupTimes"]),
    ("is the log full",                                ["Get-TransactionLogSizeAndUsage",
                                                        "Get-LogReuseWaits"]),
]

# --- HOLDOUT: not inspected while tuning -------------------------------------------------
# Written at the same sitting as TUNE, then left alone.
HOLDOUT = [
    ("who are the sysadmins on this box",              ["Get-SysadminMembers"]),
    ("can you show me sysadmin logins",                ["Get-SysadminMembers"]),
    ("when did each database last get backed up",      ["Get-LastDatabaseBackupTimes"]),
    ("anything useful for checking backups",           ["Get-BackupCoverage",
                                                        "Get-LastDatabaseBackupTimes"]),
    ("whats blocking everything",                      ["Get-BlockingChains",
                                                        "Get-BlockingSessions"]),
    ("find me the head blocker",                       ["Get-BlockingChains"]),
    ("server is slow what do I run",                   ["Get-WaitStatistics",
                                                        "Get-TopCpuQueries"]),
    ("indexes nobody uses",                            ["Get-UnusedIndexes"]),
    ("indexes that are missing",                       ["Get-MissingIndexes"]),
    ("how fragmented are my indexes",                  ["Get-IndexFragmentation"]),
    ("running out of disk",                            ["Get-DiskSpace",
                                                        "Get-DiskSpaceSummary"]),
    ("which db is eating the most space",              ["Get-DatabaseSizesAndFreeSpace",
                                                        "Get-DatabaseFreeSpaceSummary"]),
    ("log file wont shrink",                           ["Get-LogReuseWaits",
                                                        "Get-TransactionLogSizeAndUsage"]),
    ("is anything corrupt",                            ["Get-LastDbccCheckdb",
                                                        "Get-SuspectPages"]),
    ("check integrity",                                ["Get-LastDbccCheckdb",
                                                        "Get-DatabaseIntegrityChecks"]),
    ("what jobs failed last night",                    ["Get-SqlAgentJobFailureSummary"]),
    ("memory settings",                                ["Get-MemoryConfigurationAndUsage"]),
    ("maxdop",                                         ["Get-MaxdopConfiguration"]),
    ("certs about to expire",                          ["Get-CertificateExpiryWarnings"]),
    ("who has been failing to log in",                 ["Get-FailedLoginSummary"]),
    ("is the availability group ok",                   ["Get-AvailabilityGroupReplicaState",
                                                        "Get-AgFailoverReadiness"]),
    ("show me io latency per database",                ["Get-DatabaseIoUsage"]),
]

# Requests for a curated SET rather than a match. The library cannot rank "the top 10
# scripts" - it has no popularity signal and the package carries no usage data - so the
# honest answer is a redirect to the catalogue, not whatever scored highest. Peter's
# "give me a list of top 10 scripts" returned Get-TopCpuQueries, matched on the word "top".
BROWSE = [
    "give me a list of top 10 scripts",
    "what are the best scripts",
    "top 5 most useful scripts",
    "list all your scripts",
    "show me everything you have",
]

QUESTIONS = TUNE + HOLDOUT
