
IF EXISTS (SELECT * FROM [tempdb].[sys].[objects]
    WHERE [name] = N'##SQLskillsStats1')
    DROP TABLE [##SQLskillsStats1];
 
IF EXISTS (SELECT * FROM [tempdb].[sys].[objects]
    WHERE [name] = N'##SQLskillsStats2')
    DROP TABLE [##SQLskillsStats2];
GO
 
SELECT [wait_type], [waiting_tasks_count], [wait_time_ms],
       [max_wait_time_ms], [signal_wait_time_ms]
INTO ##SQLskillsStats1
FROM sys.dm_os_wait_stats;
GO
 
WAITFOR DELAY '23:59:59';
GO
 
SELECT [wait_type], [waiting_tasks_count], [wait_time_ms],
       [max_wait_time_ms], [signal_wait_time_ms]
INTO ##SQLskillsStats2
FROM sys.dm_os_wait_stats;
GO
 
WITH [DiffWaits] AS
(SELECT
-- Waits that weren't in the first snapshot
        [ts2].[wait_type],
        [ts2].[wait_time_ms],
        [ts2].[signal_wait_time_ms],
        [ts2].[waiting_tasks_count]
    FROM [##SQLskillsStats2] AS [ts2]
    LEFT OUTER JOIN [##SQLskillsStats1] AS [ts1]
        ON [ts2].[wait_type] = [ts1].[wait_type]
    WHERE [ts1].[wait_type] IS NULL
    AND [ts2].[wait_time_ms] > 0
UNION
SELECT
-- Diff of waits in both snapshots
        [ts2].[wait_type],
        [ts2].[wait_time_ms] - [ts1].[wait_time_ms] AS [wait_time_ms],
        [ts2].[signal_wait_time_ms] - [ts1].[signal_wait_time_ms] AS [signal_wait_time_ms],
        [ts2].[waiting_tasks_count] - [ts1].[waiting_tasks_count] AS [waiting_tasks_count]
    FROM [##SQLskillsStats2] AS [ts2]
    LEFT OUTER JOIN [##SQLskillsStats1] AS [ts1]
        ON [ts2].[wait_type] = [ts1].[wait_type]
    WHERE [ts1].[wait_type] IS NOT NULL
    AND [ts2].[waiting_tasks_count] - [ts1].[waiting_tasks_count] > 0
    AND [ts2].[wait_time_ms] - [ts1].[wait_time_ms] > 0),
[Waits] AS
    (SELECT
        [wait_type],
        [wait_time_ms] / 1000.0 AS [WaitS],
        ([wait_time_ms] - [signal_wait_time_ms]) / 1000.0 AS [ResourceS],
        [signal_wait_time_ms] / 1000.0 AS [SignalS],
        [waiting_tasks_count] AS [WaitCount],
        100.0 * [wait_time_ms] / SUM ([wait_time_ms]) OVER() AS [Percentage],
        ROW_NUMBER() OVER(ORDER BY [wait_time_ms] DESC) AS [RowNum]
    FROM [DiffWaits]
    WHERE [wait_type] NOT IN (
        N'CLR_SEMAPHORE',    N'LAZYWRITER_SLEEP',
        N'RESOURCE_QUEUE',   N'SQLTRACE_BUFFER_FLUSH',
        N'SLEEP_TASK',       N'SLEEP_SYSTEMTASK',
        N'WAITFOR',          N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
        N'CHECKPOINT_QUEUE', N'REQUEST_FOR_DEADLOCK_SEARCH',
        N'XE_TIMER_EVENT',   N'XE_DISPATCHER_JOIN',
        N'LOGMGR_QUEUE',     N'FT_IFTS_SCHEDULER_IDLE_WAIT',
        N'BROKER_TASK_STOP', N'CLR_MANUAL_EVENT',
        N'CLR_AUTO_EVENT',   N'DISPATCHER_QUEUE_SEMAPHORE',
        N'TRACEWRITE',       N'XE_DISPATCHER_WAIT',
        N'BROKER_TO_FLUSH',  N'BROKER_EVENTHANDLER',
        N'FT_IFTSHC_MUTEX',  N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
        N'DIRTY_PAGE_POLL',  N'SP_SERVER_DIAGNOSTICS_SLEEP',
                N'BROKER_RECEIVE_WAITFOR', N'DBMIRROR_EVENTS_QUEUE')
    )
SELECT
    [W1].[wait_type] AS [WaitType],
    CAST ([W1].[WaitS] AS DECIMAL(14, 2)) AS [Wait_S],
    CAST ([W1].[ResourceS] AS DECIMAL(14, 2)) AS [Resource_S],
    CAST ([W1].[SignalS] AS DECIMAL(14, 2)) AS [Signal_S],
    [W1].[WaitCount] AS [WaitCount],
    CAST ([W1].[Percentage] AS DECIMAL(4, 2)) AS [Percentage],
    CAST (([W1].[WaitS] / [W1].[WaitCount]) AS DECIMAL (14, 4)) AS [AvgWait_S],
    CAST (([W1].[ResourceS] / [W1].[WaitCount]) AS DECIMAL (14, 4)) AS [AvgRes_S],
    CAST (([W1].[SignalS] / [W1].[WaitCount]) AS DECIMAL (14, 4)) AS [AvgSig_S]
FROM [Waits] AS [W1]
INNER JOIN [Waits] AS [W2]
    ON [W2].[RowNum] <= [W1].[RowNum]
GROUP BY [W1].[RowNum], [W1].[wait_type], [W1].[WaitS],
    [W1].[ResourceS], [W1].[SignalS], [W1].[WaitCount], [W1].[Percentage]
HAVING SUM ([W2].[Percentage]) - [W1].[Percentage] < 95; -- percentage threshold
GO
 
-- Cleanup
IF EXISTS (SELECT * FROM [tempdb].[sys].[objects]
    WHERE [name] = N'##SQLskillsStats1')
    DROP TABLE [##SQLskillsStats1];
 
IF EXISTS (SELECT * FROM [tempdb].[sys].[objects]
    WHERE [name] = N'##SQLskillsStats2')
    DROP TABLE [##SQLskillsStats2];
GO
