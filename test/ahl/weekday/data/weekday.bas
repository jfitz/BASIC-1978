10 PRINT TAB(32);"WEEKDAY"
20 PRINT TAB(15);"CREATIVE COMPUTING  MORRISTOWN, NEW JERSEY"
30 PRINT:PRINT:PRINT
100 PRINT "WEEKDAY IS A COMPUTER DEMONSTRATION THAT"
110 PRINT"GIVES FACTS ABOUT A DATE OF INTEREST TO YOU."
120 PRINT
130 PRINT "ENTER TODAY'S DATE IN THE FORM: 3,24,1979  ";
140 INPUT M1,D1,Y1
150 REM THIS PROGRAM DETERMINES THE DAY OF THE WEEK
160 REM  FOR A DATE AFTER 1582
170 DEF FNA(A)=INT(A/4)
180 DIM T(12)
190 DEF FNB(A)=INT(A/7)
200 REM SPACE OUTPUT AND READ IN INITIAL VALUES FOR MONTHS.
210 FOR I= 1 TO 12
220 READ T(I)
230 NEXT I
240 PRINT"ENTER DAY OF BIRTH (OR OTHER DAY OF INTEREST)";
250 INPUT M,D,Y
260 PRINT
270 LET I1 = INT((Y-1500)/100)
280 REM TEST FOR DATE BEFORE CURRENT CALENDAR.
290 IF Y-1582 <0 THEN 1300
300 LET A = I1*5+(I1+3)/4
310 LET I2=INT(A-FNB(A)*7)
320 LET Y2=INT(Y/100)
330 LET Y3 =INT(Y-Y2*100)
340 LET A =Y3/4+Y3+D+T(M)+I2
350 LET B=INT(A-FNB(A)*7)+1
360 IF M > 2 THEN 470
370 IF Y3 = 0 THEN 440
380 LET T1=INT(Y-FNA(Y)*4)
390 IF T1 <> 0 THEN 470
400 IF B<>0 THEN 420
410 LET B=6
420 LET B = B-1
430 GOTO 470
440 LET A = I1-1
450 LET T1=INT(A-FNA(A)*4)
460 IF T1 = 0 THEN 400
470 IF B <>0 THEN 490
480 LET B = 7
490 IF (Y1*12+M1)*31+D1<(Y*12+M)*31+D THEN 550
500 IF (Y1*12+M1)*31+D1=(Y*12+M)*31+D THEN 530
510 PRINT M;"/";D;"/";Y;" WAS A ";
520 GOTO 570
530 PRINT M;"/";D;"/";Y;" IS A ";
540 GOTO 570
550 PRINT M;"/";D;"/";Y;" WILL BE A ";
560 REM PRINT THE DAY OF THE WEEK THE DATE FALLS ON.
570 IF B <>1 THEN 590
580 PRINT "SUNDAY."
590 IF B<>2 THEN 610
600 PRINT "MONDAY."
610 IF B<>3 THEN 630
620 PRINT "TUESDAY."
630 IF B<>4 THEN 650
640 PRINT "WEDNESDAY."
650 IF B<>5 THEN 670
660 PRINT "THURSDAY."
670 IF B<>6 THEN 690
680 GOTO 1250
690 IF B<>7 THEN 710
700 PRINT "SATURDAY."
710 IF (Y1*12+M1)*31+D1=(Y*12+M)*31+D THEN 1120
720 LET I5=Y1-Y
730 PRINT
740 LET I6=M1-M
750 LET I7=D1-D
760 IF I7>=0 THEN 790
770 LET I6= I6-1
780 LET I7=I7+30
790 IF I6>=0 THEN 820
800 LET I5=I5-1
810 LET I6=I6+12
820 IF I5<0 THEN 1310
830 IF I7 <> 0 THEN 850
835 IF I6 <> 0 THEN 850
840 PRINT"***HAPPY BIRTHDAY***"
850 PRINT " "," ","YEARS","MONTHS","DAYS"
855 PRINT " "," ","-----","------","----"
860 PRINT "YOUR AGE (IF BIRTHDATE) ",I5,I6,I7
870 LET A8 = (I5*365)+(I6*30)+I7+INT(I6/2)
880 LET K5 = I5
890 LET K6 = I6
900 LET K7 = I7
910 REM CALCULATE RETIREMENT DATE.
920 LET E = Y+65
930 REM CALCULATE TIME SPENT IN THE FOLLOWING FUNCTIONS.
940 LET F = .35
950 PRINT "YOU HAVE SLEPT ",
960 GOSUB 1370
970 LET F = .17
980 PRINT "YOU HAVE EATEN ",
990 GOSUB 1370
1000 LET F = .23
1010 IF K5 > 3 THEN 1040
1020 PRINT "YOU HAVE PLAYED",
1030 GOTO 1080
1040 IF K5 > 9 THEN 1070
1050 PRINT "YOU HAVE PLAYED/STUDIED",
1060 GOTO  1080
1070 PRINT "YOU HAVE WORKED/PLAYED",
1080 GOSUB 1370
1085 GOTO 1530
1090 PRINT "YOU HAVE RELAXED ",K5,K6,K7
1100 PRINT 
1110 PRINT TAB(16);"***  YOU MAY RETIRE IN";E;" ***"
1120 PRINT
1140 PRINT
1200 PRINT
1210 PRINT
1220 PRINT
1230 PRINT
1240 STOP
1250 IF D=13 THEN 1280
1260 PRINT "FRIDAY."
1270 GOTO 710
1280 PRINT "FRIDAY THE THIRTEENTH---BEWARE!"
1290 GOTO 710
1300 PRINT "NOT PREPARED TO GIVE DAY OF WEEK PRIOR TO MDLXXXII. "
1310 GOTO 1140
1320 REM TABLE OF VALUES FOR THE MONTHS TO BE USED IN CALCULATIONS.
1330 DATA 0, 3, 3, 6, 1, 4, 6, 2, 5, 0, 3, 5
1340 REM THIS IS THE CURRENT DATE USED IN THE CALCULATIONS.
1350 REM THIS IS THE DATE TO BE CALCULATED ON.
1360 REM CALCULATE TIME IN YEARS, MONTHS, AND DAYS
1370 LET K1=INT(F*A8)
1380 LET I5 = INT(K1/365)
1390 LET K1 = K1- (I5*365)
1400 LET I6 = INT(K1/30)
1410 LET I7 = K1 -(I6*30)
1420 LET K5 = K5-I5
1430 LET K6 =K6-I6
1440 LET K7 = K7-I7
1450 IF K7>=0 THEN 1480
1460 LET K7=K7+30
1470 LET K6=K6-1
1480 IF K6>0 THEN 1510
1490 LET K6=K6+12
1500 LET K5=K5-1
1510 PRINT I5,I6,I7
1520 RETURN
1530 IF K6=12 THEN 1550
1540 GOTO 1090
1550 LET K5=K5+1
1560 LET K6=0
1570 GOTO 1090
1580 REM
1590 END
