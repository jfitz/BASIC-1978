10 REM LENGTH OF ARRAY
20 OPTION BASE 0
22 LET B = 0
50 DATA 3
52 DATA "THREE", "FOUR", "EIGHT", "TEN"
60 GOSUB 400
70 DATA 15
72 DATA "ONE", "ZERO", "TWO", "MINUS ONE", "THREE", "ZERO", "ZERO", "FIVE"
73 DATA "TWO", "ONE", "FOUR", "MINUS THREE", "ONE", "ZERO", "FIVE", "ZERO"
80 GOSUB 400
120 OPTION BASE 1
122 LET B = 1
150 DATA 4
152 DATA "NINE", "THREE", "FOUR", "EIGHT"
160 GOSUB 400
170 DATA 16
172 DATA "FOUR", "ONE", "ZERO", "TWO", "MINUS ONE", "THREE", "ZERO", "ZERO"
173 DATA "FIVE", "TWO", "ONE", "FOUR", "MINUS THREE", "ONE", "ZERO", "FIVE"
180 GOSUB 400
199 STOP
400 READ N
420 ARR READ A$(N)
460 PRINT "ARRAY:"
470 ARR PRINT A$
480 LET L = NELEM(A$)
490 PRINT "LENGTH:" L
495 PRINT
499 RETURN
999 END

