10 DIM A%(5,6)
20 OPTION BASE 0
30 MAT READ A%
40 MAT B% = SORT2%(A%)
50 GOSUB 800
90 REM RESTORE
120 OPTION BASE 1
130 MAT READ A%
140 MAT B% = SORT2%(A%)
150 GOSUB 800
790 STOP
800 REM PROCEDURE A
810 PRINT "MATRIX A"
820 MAT PRINT A%
830 PRINT "MATRIX B"
840 MAT PRINT B%
890 RETURN
900 DATA 3%,10%,23%,30%,40%,50%,60%
901 DATA 3%,10%,22%,30%,40%,50%,60%
902 DATA 1%,10%,20%,30%,40%,50%,60%
903 DATA 3%,10%,21%,30%,40%,50%,60%
904 DATA 0%,10%,20%,30%,40%,50%,60%
905 DATA 0%,10%,20%,30%,40%,50%,60%
910 DATA 3%,10%,23%,30%,40%,50%
911 DATA 3%,10%,22%,30%,40%,50%
912 DATA 1%,10%,20%,30%,40%,50%
913 DATA 3%,10%,21%,30%,40%,50%
914 DATA 0%,10%,20%,30%,40%,50%
999 END
