10 REM TEST MULTILINE USER FUNCTION
20 PRINT "START"
30 A = FNA(100)
40 PRINT "A IS:"; A
90 PRINT "END"
100 DEF FNA(H)
110 PRINT "START FNA()"
115 DEF FNR(X)=INT(RND(X)*10)
120 FNA = H - 9
130 PRINT "END FNA()"
140 ENDFN
999 END
