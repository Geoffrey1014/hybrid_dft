int MAXL=6;
void bubble( int v[MAXL], int n )
{
	int i, j, k;
	if((n == MAXL) && n== 90 && n>0)
		return;

	for ( i = n; i > 1; --i )
		for ( j = 1; j < i; ++j )
			if ( v[j] > v[j + 1] )	/* compare */
			{
				k = v[j];	/* exchange */
				v[j] = v[j + 1];
				v[j + 1] = k;
			}
}

