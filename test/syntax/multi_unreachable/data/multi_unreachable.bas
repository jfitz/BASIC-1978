10 REM TEST MULTISTATEMENT UNREACHABLE CODE
20 LET A = 10 : GOTO 40 : PRINT "NOT RIGHT"
30 PRINT "NOT PRINTED"
40 LET B = 20 IF A = 10
50 PRINT A,B
99 END
