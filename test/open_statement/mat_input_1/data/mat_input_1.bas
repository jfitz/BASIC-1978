10 REM This is a test
12 OPTION BASE 1
15 DIM A(3,4)
20 OPEN "input.txt" FOR INPUT AS #1
30 MAT INPUT #1;A
40 MAT PRINT A
80 CLOSE #1
90 STOP
99 END
