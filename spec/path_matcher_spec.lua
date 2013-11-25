local pm = require'jet.daemon.path_matcher'

describe(
  'The jet.daemon.path_matcher module',
  function()
    
    describe('(private) _is_partial',function()
        it('matches',function()
            assert.is_equal(pm._is_partial('foo'),'foo')
            assert.is_equal(pm._is_partial('foo*'),'foo')
            assert.is_equal(pm._is_partial('*foo'),'foo')
            assert.is_equal(pm._is_partial('*foo*'),'foo')
          end)
        
        it('mismatches',function()
            assert.is_falsy(pm._is_partial('^foo*'))
            assert.is_falsy(pm._is_partial('foo$'))
            assert.is_falsy(pm._is_partial('*foo$'))
          end)
      end)
    
    describe('(private) _escape',function()
        it('works',function()
            assert.is_equal(pm._escape('foo'),'foo')
            assert.is_equal(pm._escape('foo*'),'foo.+')
            assert.is_equal(pm._escape('*foo'),'.+foo')
            assert.is_equal(pm._escape('*foo*'),'.+foo.+')
            assert.is_equal(pm._escape('foo$'),'foo$')
          end)
      end)
    
    describe('An exact path matcher',function()
        local match
        
        setup(function()
            match = pm.new({
                match = {
                  '^somepath$'
                }
            })
          end)
        
        it('matches',function()
            assert.is_true(match('somepath'))
          end)
        
        it('mismatches',function()
            assert.is_falsy(match('somePath'))
            assert.is_falsy(match('somepathsomepath'))
            assert.is_falsy(match('some*path'))
            assert.is_falsy(match('^somepath'))
            assert.is_falsy(match('^somepath$'))
          end)
        
      end)
    
    describe('Multiple exact path matcher',function()
        local match
        
        setup(function()
            match = pm.new({
                match = {
                  '^somepath$',
                  '^foobar$',
                }
            })
          end)
        
        it('matches',function()
            assert.is_true(match('somepath'))
            assert.is_true(match('foobar'))
          end)
        
        it('mismatches',function()
            assert.is_falsy(match('somePath'))
            assert.is_falsy(match('somepathsomepath'))
            assert.is_falsy(match('some*path'))
            assert.is_falsy(match('^somepath'))
            assert.is_falsy(match('^somepath$'))
          end)
        
      end)
    
    describe('A partial path matcher',function()
        local match
        
        setup(function()
            match = pm.new({
                match = {
                  'somewhere'
                }
            })
            
          end)
        
        it('matches',function()
            assert.is_true(match('somewhere'))
            assert.is_true(match('somewhereA'))
            assert.is_true(match('abcsomewhere123'))
            assert.is_true(match('abcsomewhere'))
          end)
        
        it('mismatches',function()
            assert.is_falsy(match('somePath'))
            assert.is_falsy(match('someOOpath'))
            assert.is_falsy(match('AAsomepath'))
            assert.is_falsy(match('asomepathb'))
          end)
      end)
    
    describe('A partial path matcher with exact unmatch',function()
        local match
        
        setup(function()
            match = pm.new({
                match = {
                  'somewhere'
                },
                unmatch = {
                  '^abcsomewhere1234$'
                }
            })
            
          end)
        
        it('matches',function()
            assert.is_true(match('somewhere'))
            assert.is_true(match('somewhereA'))
            assert.is_true(match('abcsomewhere123'))
            assert.is_true(match('abcsomewhere'))
          end)
        
        it('mismatches',function()
            assert.is_falsy(match('abcsomewhere1234'))
            assert.is_falsy(match('somePath'))
            assert.is_falsy(match('someOOpath'))
            assert.is_falsy(match('AAsomepath'))
            assert.is_falsy(match('asomepathb'))
          end)
      end)
    
    describe('A partial path matcher with partial unmatch',function()
        local match
        
        setup(function()
            match = pm.new({
                match = {
                  'somewhere'
                },
                unmatch = {
                  '1234'
                }
            })
            
          end)
        
        it('matches',function()
            assert.is_true(match('somewhere'))
            assert.is_true(match('somewhereA'))
            assert.is_true(match('abcsomewhere123'))
            assert.is_true(match('abcsomewhere'))
          end)
        
        it('mismatches',function()
            assert.is_falsy(match('abcsomewhere1234'))
            assert.is_falsy(match('1234somewhere'))
            assert.is_falsy(match('somePath'))
            assert.is_falsy(match('someOOpath'))
            assert.is_falsy(match('AAsomepath'))
            assert.is_falsy(match('asomepathb'))
          end)
      end)
    
    describe('A left-bound partial path matcher',function()
        local match
        
        setup(function()
            match = pm.new({
                match = {
                  '^somepath'
                }
            })
            
          end)
        
        it('matches',function()
            assert.is_true(match('somepath'))
            assert.is_true(match('somepathFoo'))
          end)
        
        it('mismatches',function()
            assert.is_falsy(match('somePath'))
            assert.is_falsy(match('someOOpath'))
            assert.is_falsy(match('AAsomepath'))
            assert.is_falsy(match('asomepathb'))
          end)
      end)
    
    describe('A right-bound partial path matcher',function()
        local match
        
        setup(function()
            match = pm.new({
                match = {
                  'somepath$'
                }
            })
          end)
        
        it('matches',function()
            assert.is_true(match('somepath'))
            assert.is_true(match('Foosomepath'))
          end)
        
        it('mismatches',function()
            assert.is_falsy(match('somePath'))
            assert.is_falsy(match('some*path'))
            assert.is_falsy(match('somepathT'))
            assert.is_falsy(match('asomepatho'))
          end)
      end)
    
  end)
