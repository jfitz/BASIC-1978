2 REM RAIL SIMULATION
10 REM ********** INITIALIZATION
11 REM ***** OPTIONS
12 OPTION REQUIRE_INITIALIZED TRUE
13 OPTION BASE 1
14 OPTION PRINT_WIDTH 132
20 REM ***** FUNCTIONS
21 REM FORMAT TIME INTO STRING
22 DEF FNH$(T) = RIGHT$("0"+STR$(INT(T/3600)),2)+":"+RIGHT$("0"+STR$(INT(MOD(T,3600)/60)),2)+":"+RIGHT$("0"+STR$(MOD(T,60)),2)
23 REM CALCULATE STOPPING TIME
24 DEF FNS(V,A) = 2.0*(ABS(V)/ABS(A))
25 REM CALCULATE STOPPING DISTANCE
26 DEF FND(V,A,T) = V*T + 0.5*(A)*T^2
70 REM ***** DATA
71 REM NUMBER OF STATIONS, POSITIONS (in meters), NAMES
72 DATA 17
73 DATA 0, 5.6E3, 13.53E3, 16.7E3, 18.2E3, 20.4E3, 24.6E3, 26.6E3, 29.3E3, 33.6E3, 35.6E3, 37.3E3, 39.6E3, 42.6E3, 44.9E3, 46.8E3, 49.1E3
74 DATA "HOBOKEN", "SEACAUCUS", "RUTHERFORD", "WESMONT", "GARFIELD", "PLAUDERVILLE", "BROADWAY", "RADBURN", "GLEN ROCK", "RIDGEWOOD", "HO_HO_KUS"
75 DATA "WALDWICK", "ALLENDALE", "RAMSEY", "RAMSEY RT17", "MAHWAH", "SUFFERN"
76 REM NUMBER OF TRACK SPEED SIGNS, POSITIONS (in meters) AND VALUES
77 DATA 7
78 DATA 0,5, 1.0E3,30, 1.5E3,50, 2.0E3,30, 2.5E3,80, 5.7E3,40, 6.0E3,80
100 REM ***** STATIONS
101 READ K0
110 DIM K(K0), K$(K0)
111 ARR READ K,K$
120 REM ***** TRAINSET
121 REM ACCELERATION (meters/second^2)
122 LET A0 = 1.0
123 REM MAX VELOCITY (meters/second)
124 LET V9 = 80
150 REM ***** SPEED SIGNALS
151 READ P0
152 DIM P(P0,2)
153 MAT READ P
200 REM ********** ONE TRIP
201 LET K5 = 1
202 LET X = K(K5)
203 LET X0 = X - 1
210 LET V = 0
290 PRINT "T      ";"TIME     ";"X  ";"V  ";"A  ";"T5 ";"X5 ";"K(2) ";"STATUS"
299 LET T = 17*60*60+2*60
1000 REM ********* LOOP
1001 LET S$ = ""
1010 REM COMPUTE STOPPING TIME
1011 LET T5 = FNS(V, A0)
1020 REM COMPUTE STOPPING DISTANCE
1021 LET X5 = FND(V, A0, T5)
1100 REM *** FIND MOST RECENT STATION
1101 K5 = 1
1102 FOR I = 1 TO K0
1103 IF X > K(I) THEN K5 = I
1104 NEXT I
1110 REM *** FIND MOST RECENT TRACK SIGN
1111 P5 = 1
1112 FOR I = 1 TO P0
1113 IF X > P(I,1) THEN P5 = I
1114 NEXT I
1200 REM *** SET MAX SPEED FOR STATION APPROACH
1201 LET V8 = V9
1202 LET K6 = K5 + 1
1203 IF K6 > K0 THEN 1210
1204 IF X < K(K6) AND X + X5 >= K(K6) THEN 1206 ' IF K(K6) IN X, X + X5 
1205 GOTO 1209
1206 LET V8 = 0
1207 LET S$ = "APPROACHING " + K$(K6)
1209 GOTO 1220
1210 REM *** NO MORE STATIONS, STOP
1211 LET V8 = 0
1220 REM *** SET MAX SPEED FROM TRACK SIGN
1221 LET V7 = V9
1222 IF P5 < P0 AND P(P5,1) > X0 AND P(P5,1) <= X THEN LET V7 = P(I,2) ' IF P(P5, 1) IN X0, X
1290 REM ***** SET MAX SPEED
1291 LET V5 = V9
1292 IF V5 > V8 THEN LET V5 = V8
1293 IF V5 > V7 THEN LET V5 = V7
1700 REM ***** ADJUST SPEED
1711 IF V > V5 THEN 1740
1712 IF V < V5 THEN 1730
1720 REM CONTINUE AT CURRENT SPEED
1721 LET A = 0
1729 GOTO 1799
1730 REM INCREASE SPEED
1731 LET A = A0
1739 GOTO 1790
1740 REM BRAKE
1741 LET A = -A0
1742 LET S$ = S$ + " BRAKING"
1790 LET V = V + A
1799 REM CONTINUE
1900 REM ***** CHECK SPEED
1901 IF V >= 0 THEN 1910
1902 LET V = 0
1910 REM ***** MOVE THE TRAIN
1911 LET X0 = X
1912 LET X = X + V
1913 REM SLOW APPROACH TO STATION MEANS STOP AT THE STATION
1913 IF V < 3 AND X > K(K6) AND X < K(K6) + 1 THEN X = K(K6)
1970 REM ***** REPORT TIME, POSITION, AND SPEED
1971 LET T$ = FNH$(T)
1972 PRINT T;T$;X;V;A;T5;X5;K(2);S$
1980 REM ***** END OF LOOP
1981 IF X >= K(2) THEN 9997
1990 REM STEP INTO FUTURE
1991 LET T = T + 1
1999 GOTO 1000
9997 REM ********** END OF SIMULATION
9998 STOP
9999 END
