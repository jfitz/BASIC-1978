10 REM This is a test
15 DIM A(3),B(5)
20 DATA 10,20,30,40
21 DATA 11,12,13,14,15,16
25 OPEN "output.txt" FOR OUTPUT AS #1
30 ARR READ A,B
40 ARR PRINT #1;A,B
80 CLOSE #1
90 STOP
99 END