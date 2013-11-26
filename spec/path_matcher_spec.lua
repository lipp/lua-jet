local pm = require'jet.daemon.path_matcher'

describe(
  'The jet.daemon.path_matcher module',
  function()
    
    describe('An exact path matcher',function()
        local match
        
        setup(function()
            local path_matcher = pm.new({
                path = {
                  equals = 'somepath'
                }
            })
            match = path_matcher
          end)
        
        it('matches',function()
            assert.is_true(match('somepath'))
          end)
        
        it('mismatches',function()
            assert.is_falsy(match('somePath'))
            assert.is_falsy(match('somepathsomepath'))
            assert.is_falsy(match('some*path'))
            assert.is_falsy(match('1somepath'))
            assert.is_falsy(match('somepath3'))
          end)
        
      end)
    
    describe('An case insensitive exact path matcher',function()
        local match
        
        setup(function()
            local path_matcher = pm.new({
                path = {
                  equals = 'somePATH',
                  caseInsensitive = true
                },
            })
            match = function(path)
              return path_matcher(path,path:lower())
            end
          end)
        
        it('matches',function()
            assert.is_true(match('somepath'))
            assert.is_true(match('somePath'))
            assert.is_true(match('somePATH'))
          end)
        
        it('mismatches',function()
            assert.is_falsy(match('somepathsomepath'))
            assert.is_falsy(match('some*path'))
          end)
        
      end)
    
    
    describe('Multiple exact path matcher',function()
        local match
        
        setup(function()
            match = pm.new({
                path = {
                  equalsOneOf = {
                    'somepath',
                    'foobar',
                  }
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
                path = {
                  contains = 'somewhere'
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
                path = {
                  contains = 'somewhere',
                  equalsNot = 'abcsomewhere1234'
                },
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
                path = {
                  contains = 'somewhere',
                  containsNot = '1234'
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
                path = {
                  startsWith = 'somepath'
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
                path = {
                  endsWith = 'somepath'
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
