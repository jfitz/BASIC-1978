10 REM This is a test
20 OPEN "input.txt" FOR INPUT AS #1
30 FOR I = 1 TO 4
40 READ #1;A$,B$,C$,D$
50 WRITE A$;B$;C$;D$
60 NEXT I
80 CLOSE #1
90 STOP
99 END
