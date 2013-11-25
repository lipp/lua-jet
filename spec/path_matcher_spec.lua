local socket = require'socket'
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
