10 DIM A(10)
20 ARR FOR I IN A
30 LET A(I) = RND(100)
40 ARR NEXT
50 ARR PRINT A
100 ARR FOR I IN A
110 PRINT "OUTER:"; I
130 PRINT A(I)
140 ARR NEXT
150 OPTION BASE 1
290 STOP
299 END