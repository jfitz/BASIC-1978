10 DIM A(6,5)
20 FOR I = 1 TO 6
30 FOR J = 1 TO 5
40 LET A(I,J) = I*10 + J
50 NEXT J
60 NEXT I
70 PRINT "MATRIX A"
72 MAT PRINT A;
80 MAT B = TRN(A)
90 PRINT "MATRIX B"
92 MAT PRINT B;
99 END
