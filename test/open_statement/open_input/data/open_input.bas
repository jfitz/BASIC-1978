10 REM TEST OPEN READ COMMANDS
20 OPEN "data.txt" FOR INPUT AS #1
30 INPUT #1, A,B,C
40 INPUT #1, N$
50 CLOSE #1
60 PRINT N$,A,B,C
99 END
