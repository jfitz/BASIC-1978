10 OPTION BASE 0
20 DIM A(6)
30 FOR I = 0 TO 6
40 LET A(I) = I*10
50 NEXT I
100 ARR B = REV1(A)
110 GOSUB 800
120 OPTION BASE 1
130 ARR B = REV1(A)
140 OPTION BASE 0
150 GOSUB 800
790 STOP
800 REM PROCEDURE A
810 PRINT "ARRAY A"
820 ARR PRINT A
830 PRINT "ARRAY B"
840 ARR PRINT B
890 RETURN
999 END