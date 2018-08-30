#*****************************************************************************
#
#    Tools to compute with Hilbert Poincare series
#
#    Copyright (C) 2018 Simon A. King <simon.king@uni-jena.de>
#
#    This file is part of p_group_cohomology.
#
#    p_group_cohomoloy is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 2 of the License, or
#    (at your option) any later version.
#
#    p_group_cohomoloy is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with p_group_cohomoloy.  If not, see <http://www.gnu.org/licenses/>.
#*****************************************************************************



from sage.all import Integer, ZZ, QQ, PolynomialRing
from pGroupCohomology.auxiliaries import singular, coho_logger
from sage.stats.basic_stats import median

# Global definitions
PR = PolynomialRing(QQ,'t')
t = PR('t')

def _FirstHilbertSeries(D, Tiefe, cmd, with_singular=True):
    """
    Compute the first Hilbert series of ``Id``, or return ``NotImplemented``

    In some base cases, the correct value will be directly returned. In other
    cases and if ``with_singular==True``, Singular will be used to compute
    the first Hilbert series. If that fails (and it certainly will fail with
    an int overflow if the ring has too many variables), then ``NotImplemented``
    is returned.

    """
    Id = D['Id']
    S = Id._check_valid()
    n = Id.name()
    cmd = cmd.format(n,'{}')
    cdef size_t i,j
    cdef ssize_t e
    # First, the easiest cases:
    if S.eval('%s[1]'%(n))=='0':
        #print "Nullcase",Id.string()
        return PR(1)
    if S.eval('%s[1]'%(n))=='1':
        #print "Onecase",Id.string()
        return PR(0)

    # Second, another reasy case: Id is generated by variables.
    # Id is sorted in dp ordering. Hence, if the last generator is a single
    # variable, then ALL are.
    if S.eval('sum(leadexp(%s[ncols(%s)]))'%(n,n))=='1':
        #print "Generator case",Id.string()
        return PR.prod([(1-t**Integer(S.eval('deg(%s[%d])'%(n,X)))) for X in range(1,Integer(S.eval('ncols(%s)'%(n)))+1)])

    # The above was the easiest case that all generators are single variables.
    # Now we give Singular a chance:
    if with_singular:
        try:
            hv = S('hilb({},1,ringweights(basering))'.format(n))
            c = '{}['.format(hv.name())+'{}]'
            #print "Singular case",Id.string()
            return PR([Integer(S.eval(c.format(i))) for i in range(1,hv.size())]) # the last entry of hv is omitted, as it is zero.
        except TypeError, msg:
            coho_logger.warn("We didn't expect Singular to fail in depth %d", "First Hilbert Series", Tiefe)

    # Fourthly, we test for proper powers of single variables, using a temporary
    # Singular intvec that is supposed to be assigned by the callee, and used
    # in the cmd string provided by the callee.
    easy = True
    for i in range(1,int(S.eval('ncols('+n+')'))+1):
        if S.eval(cmd.format(i))=='0': # i.e., the generator contains more than a single var
            easy = False
            break
    if easy:
        # The ideal is generated by some powers of single variables, i.e., it splits.
        #print "Power case",Id.string()
        return PR.prod([(1-t**Integer(S.eval('deg(%s[%d])'%(n,X)))) for X in range(1,Integer(S.eval('ncols(%s)'%(n)))+1)])

    easy = True
    cdef list v
    for j in range(i+1,int(S.eval('ncols('+n+')'))+1):
        if S.eval(cmd.format(j))=='0': # i.e., another generator contains more than a single var
            easy = False
            break
    if easy:
        # The ideal only has a single non-simple power, in position i.
        # Since the ideal is interreduced and all other monomials are
        # simple powers, they belong to different 
        v = [Integer(x) for x in S.eval('string(leadexp(product({})/({}[{}]))-leadexp({}[{}]))'.format(n,n,i,n,i)).split(',')]
        Factor = PR.one()
        for j,e in enumerate(v):
            if e>0:
                Factor *= (1-t**(e*Integer(S.eval('deg(var({}))'.format(j+1)))))
        #print "one-list case",Id.string()
        return PR.prod([1-t**Integer(S.eval('deg(%s[%d])'%(n,j))) for j in range(1,Integer(S.eval('ncols(%s)'%n))+1) if i!=j]) - t**Integer(S.eval('deg(%s[%d])'%(n,i)))*Factor
    # Now we are in a truly difficult case. We give up for now...
    return NotImplemented

cdef make_children(dict D, str cmd):
    """
    Create child nodes that allow to compute the first Hilbert series of ``self.Id``
    """
    Id = D['Id']
    S = Id._check_valid()
    n = Id.name()
    cdef size_t j,i
    # Determine the variable that appears most often in the monomials.
    # If "most often" means "only once", then instead we choose a variable that is
    # guaranteed to appear in a composed monomial.
    # We will raise it to a reasonably high power that still guarantees that
    # many monomials will be divisible by it.
    cdef list LE = [Integer(x) for x in S.eval('string(leadexp(product({})))'.format(n)).split(',')]
    m = max(LE)
    print([i for i in range(len(LE)) if LE[i]==m])
    e = None # will be the exponent, as a string
    cdef list exps
    #print "Id:",Id.string()
    if m>1:
        j = LE.index(m)+1
        exps = [Integer(S.eval('leadexp(%s[%d])[%d]'%(n,i,j))) for i in range(Integer(S.eval('ncols(%s)'%n)),0,-1)]
        e = median([x for x in exps if x]).floor()
        if S.eval('NF(var(%d)**%d,%s)'%(j,e,n))=='0':
            # If var(j)**e is a generator, then e is the maximal exponent of var(j) in Id, by
            # Id being interreduced. But it also is the truncated median, hence, there cannot
            # be smaller exponents (for otherwise the median would be strictly smaller than the maximum).
            # Conclusion: var(j) only appears in the generator var(j)**e -- we have a split case.
            #print 'Generator split case', S.eval('var(%d)**%d'%(j,e))
            D['LMult'] = 1-t**(e*Integer(S.eval('deg(var(%d))'%(j))))
            D['Left']  = {'Id':S('simplify(NF(%s,std(var(%d)**%d)),2)'%(n,j,e)), 'Back':D}
            S.eval('attrib(%s,"isSB",1)'%D['Left']['Id'].name())
            D['Right'] = None
        else:
            #print 'Regular case', S.eval('var(%d)**%d'%(j,e))
            if e>1:
                D['LMult'] = 1
                D['Left']  = {'Id':S('sort(interred(NF(%s,std(var(%d)**%d)))+var(%d)**%d,"dp")[1]'%(n,j,e,j,e)), 'Back':D}
                S.eval('attrib(%s,"isSB",1)'%D['Left']['Id'].name())
                D['Right'] = {'Id':S('sort(interred(quotient(%s,var(%d)**%d)),"dp")[1]'%(n,j,e)), 'Back':D}
            else:
                # m>1, therefor var(j) cannot be a generator (Id is interreduced).
                # Id+var(j) will be a split case. So, we do the splitting right now.
                D['LMult'] = 1-t**Integer(S.eval('deg(var(%d))'%(j)))
                D['Left']  = {'Id':S('simplify(NF(%s,std(var(%d))),2)'%(n,j)), 'Back':D}
                S.eval('attrib(%s,"isSB",1)'%D['Left']['Id'].name())
                D['Right'] = {'Id':S('sort(interred(%s+ideal(%s/var(%d))),"dp")[1]'%(n,n,j)), 'Back':D}
            S.eval('attrib(%s,"isSB",1)'%D['Right']['Id'].name())
            D['RMult'] = t**(e*Integer(S.eval('deg(var(%d))'%(j))))
    else:
        LE = [Integer(x) for x in S.eval('leadexp({}[ncols({})])'.format(n,n)).split(',')]
        e = 1
        for j in LE:
            if j:
                break
        # m==1, therefor var(j) only appears in the last generator, which however
        # contains more than var(j). Since Id is interreduced, var(j) cannot
        # be a generator.
        # Id+var(j) will be a split case. So, we do the splitting right now.
        # Only the last generator contains var(j). Hence, Id/var(j) is obtained
        # from Id by adding the quotient of its last generator divided by var(j),
        # of course followed by interreduction.
        #print "Simple split case", S.eval('var(%d)'%j)
        D['LMult'] = 1-t**Integer(S.eval('deg(var(%d))'%(j)))
        D['Left']  = {'Id':S('simplify(NF(%s,std(var(%d))),2)'%(n,j)), 'Back':D}
        S.eval('attrib(%s,"isSB",1)'%D['Left']['Id'].name())
        # For the quotient by a single variable, the following is faster than monomial_quotient(Id,var(j)),
        # which in turn is faster than quotient(Id,var(j)):
        D['Right'] = {'Id':S('sort(interred(%s+%s[ncols(%s)]/var(%d)),"dp")[1]'%(n,n,n,j)), 'Back':D}
        S.eval('attrib(%s,"isSB",1)'%D['Right']['Id'].name())
        D['RMult'] = 1-D['LMult']

def FirstHilbertSeries(I, try_singular=True):
    """
    Return the first Hilbert series of the given weighted homogeneous ideal.

    INPUT:

    ``I``: an ideal or its name in singular, weighted homogeneous with respect
           to the degree of the ring variables.

    OUTPUT:

    A univariate polynomial, namely the first Hilbert function of ``I``.

    EXAMPLES::

        sage: from pGroupCohomology.hilbert import FirstHilbertSeries
        sage: R = singular.ring(0,'(x,y,z)','dp')
        sage: I = singular.ideal(['x^2','y^2','z^2'])
        sage: FirstHilbertSeries(I)
        -t^6 + 3*t^4 - 3*t^2 + 1
        sage: FirstHilbertSeries(I.name())
        -t^6 + 3*t^4 - 3*t^2 + 1

    """
    if isinstance(I,basestring):
        S = singular
        I = S(I)
    else:
        S = I._check_valid()
    with_singular = try_singular
    if with_singular:
        try:
            hv = S('hilb(maxideal(1),1,ringweights(basering))')
        except TypeError:
            with_singular = False
            coho_logger.warn('Singular has an int overflow; we are working around', "First Hilbert Series")
    # The "active node". If a recursive computation is needed, it will be equipped
    # with a 'Left' and a 'Right' child node, and some 'Multipliers'. Later, the first Hilbert
    # series of the left child node will be stored in 'LeftFHS', and together with
    # the first Hilbert series of the right child node and the multiplier yields
    # the first Hilbert series of 'Id'.
    cdef dict AN

    # First, we need to deal with quotient rings, which also covers the case
    # of graded commutative rings that arise as cohomology rings in odd characteristic.
    # We replace everything by a commutative version of the quotient ring.
    br = S('basering')  # not catching an exception here.
    try:
        if S.eval('isQuotientRing(basering)')=='1':
            L = singular('ringlist(basering)')
            R = singular('ring(list(%s[1..3],ideal(0)))'%L.name())
            R.set_ring()
            AN = {'Id':singular('sort(interred(lead(fetch(%s,%s)+ideal(%s))),"dp")[1]'%(br.name(),I.name(),br.name())), 'Back':None}
        else:
            AN = {'Id':singular('sort(interred(lead(%s)),"dp")[1]'%(I.name())), 'Back':None}
        S.eval('attrib(%s,"isSB",1)'%AN['Id'].name())
        nvars = S.eval('nvars(basering)')
        tmp = S.intvec(0)
        tmpn = tmp.name()
        cmd = tmpn+'=leadexp({}[{}]);' + 'sum({})==max({}[1..{}])'.format(tmpn,tmpn,nvars)

        # Invariant of this function:
        # At each point, fhs will either be NotImplemented or the first Hilbert series of AN.
        Tiefe = 0
        MaximaleTiefe = 0
        fhs = _FirstHilbertSeries(AN,Tiefe,cmd,with_singular)
        while True:
            if fhs is NotImplemented:
                make_children(AN,cmd)
                AN = AN['Left']
                Tiefe += 1
                MaximaleTiefe = max(MaximaleTiefe, Tiefe)
                fhs = _FirstHilbertSeries(AN,Tiefe,cmd,with_singular)
            else:
                if AN['Back'] is None: # We are back on top, i.e., fhs is the First Hilber Series of I
                    coho_logger.debug('Maximal depth of recursion: %d', "First Hilbert Series", MaximaleTiefe)
                    return fhs
                if AN is AN['Back']['Left']: # We store fhs and proceed to the sibling
                    # ... unless there is no sibling
                    if AN['Back']['Right'] is None:
                        AN = AN['Back']
                        fhs *= AN['LMult']
                    else:
                        AN['Back']['LeftFHS'] = fhs
                        AN = AN['Back']['Right']
                        AN['Back']['Left'] = None
                        fhs = _FirstHilbertSeries(AN,Tiefe,cmd,with_singular)
                else: # FHS of the left sibling is stored, of the right sibling is known.
                    AN = AN['Back']
                    AN['Right'] = None
                    Tiefe -= 1
                    fhs = AN['LMult']*AN['LeftFHS'] + AN['RMult']*fhs
    finally:
        try:
            br.set_ring()
        except:
            pass

def HilbertPoincareSeries(I, with_singular=True):
    r"""
    Return the Hilbert Poincaré series of the given weighted homogeneous ideal.
    """
    HP = FirstHilbertSeries(I,with_singular)
    if isinstance(I,basestring):
        S = singular
    else:
        S = I._check_valid()
    dv = [Integer(d) for d in S.eval('ringweights(basering)').split(',')]
    HS = HP/PR.prod([(1-t**d) for d in dv])
    if HS.denominator().leading_coefficient()<0:
        return (-HS.numerator()/(-HS.denominator()))
    return HS