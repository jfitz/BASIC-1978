10 REM TEST PROGRAM FOR CHR$() FUNCTION
20 READ A$
30 IF A$="STOP" THEN 99
40 LET A%=ASC%(A$)
50 PRINT "ASC("; A$; ") IS "; A%
60 GOTO 20
90 DATA "HELLO, WORLD!", "A", "LONG STRING WITH LOTS OF TEXT", "", "STOP"
99 END

