10 REM TEST DEF FN WITH INTEGER ARGS
20 DEF FNI0$(S$,I%)=MID$(S$,I%,1%)
100 A$="HELLO, WORLD!"
110 PRINT "STRING IS: [";A$;"]"
120 B% = 3%
130 PRINT "INDEX IS: ";B%
140 C$=FNI0$(A$,B%)
150 PRINT "CHAR IS: "; C$
999 END
