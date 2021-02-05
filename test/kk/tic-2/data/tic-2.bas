70   REM THIS IS PROGRAM TIC-2
80
90   REM INITIALIZER
100  FOR P = 1 TO 8
110     FOR I = 1 TO 3
120        READ T(P,I)
130     NEXT I
140  NEXT P
150  DATA 1,2,3,8,9,4,7,6,5,1,8,7,2,9,6,3,4,5,1,9,5,7,9,3
200  FOR S = 1 TO 9
210     FOR J = 1 TO 4
220        READ U(S,J)
230     NEXT J
240  NEXT S
250  DATA 1,4,7,0,1,5,0,0,1,6,8,0,2,6,0,0,3,6,7,0
260  DATA 3,5,0,0,3,4,8,0,2,4,0,0,2,5,7,8
265  LET N = 0
270  FOR S = 1 TO 9
275     LET C(S) = 0
280     LET B(S) = 0
285  NEXT S
290
300  REM WHO STARTS?
310  IF RND(Z) < 1/2 THEN 350
320  PRINT "YOU WILL MOVE FIRST."
330  PRINT
340  GOTO 400
350  PRINT "THE COMPUTER WILL MOVE FIRST."
360  PRINT
370  GOTO 600
380
390  REM PLAYER'S MOVE.
400  PRINT "YOUR MOVE";
410  INPUT M
415  LET F = -1
420  IF M <> INT(M) THEN 550
430  IF M < 1 THEN 500
440  IF M > 9 THEN 550
450  IF B(M) <> 0 THEN 500
460  LET B(M) = F
470  FOR J = 1 TO 4
480     LET P = U(M,J)
490     IF P = 0 THEN 530
500     LET C(P) = C(P) + F
510     IF C(P) = -3 THEN 860
520     IF C(P) = 3 THEN 800
530  NEXT J
535  LET N = N+1
536  IF N = 9 THEN 880
537  IF F = 1 THEN 400
538  GOTO 600
540  GOTO 600
550  PRINT "ILLEGAL MOVE. TRY AGAIN."
560  GOTO 400
595
600  REM MACHINE'S MOVE
610  GOSUB 1000
620  PRINT "THE COMPUTER MOVES" M
630  LET F = 1
640  GOTO 460
800  REM THE GAME IS OVER
810  PRINT "AND THE COMPUTER WINS."
820  PRINT
830  PRINT
840  PRINT "NEW GAME."
850  GOTO 265
860  PRINT "CONGRATULATIONS, YOU BEAT THE COMPUTER."
870  GOTO 820
880  PRINT "THE GAME IS A DRAW."
890  GOTO 820
895
1000 REM SELECT A MOVE
1010 FOR P = 1 TO 8
1020 IF C(P) = 2 THEN 1100
1030 NEXT P
1040 FOR P = 1 TO 8
1050 IF C(P) = -2 THEN 1100
1060 NEXT P
1070 GOTO 1200
1100 FOR I = 1 TO 3
1110    LET M = T(P,I)
1120    IF B(M) = 0 THEN 1999
1130 NEXT I
1140
1200 FOR S = 1 TO 9
1210    LET V(S) = 0
1215    IF B(S) <> 0 THEN 1270
1220    FOR J = 1 TO 4
1230       LET P = U(S,J)
1240       IF P = 0 THEN 1260
1250       LET V(S) = V(S) + 1 + ABS(C(P))
1260    NEXT J
1270 NEXT S
1300 LET V = 0
1310 FOR S = 1 TO 9
1320    IF V(S) <= V THEN 1350
1330    LET V = V(S)
1340    LET M = S
1350 NEXT S
1999 RETURN
9999 END
