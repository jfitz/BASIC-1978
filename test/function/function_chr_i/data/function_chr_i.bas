10 REM TEST PROGRAM FOR CHR$() FUNCTION
20 READ N%
30 IF N%=0% THEN 99
40 LET A$=CHR$(N%)
50 PRINT "CHR$("; N%; ") IS '"; A$; "'"
60 GOTO 20
90 DATA 32%, 48%, 64%, 65%, 66%, 90%, 97%, 122%, 126%
91 DATA 70.3, 0%
99 END

