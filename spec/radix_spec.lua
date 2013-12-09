local radix = require'jet.daemon.radix'

describe(
  'The jet.daemon.radix module',
  function()
    
    describe('Can add path',function()
        local match
        
        setup(function()
            local radix_tree = radix.new()
            radix_tree.add('abc')
            local radix_fetchers = {}
            radix_fetchers['equals'] = 'abc'
            radix_tree.match_parts(radix_fetchers)
            match = radix_tree.found_elements()['abc']
          end)
        
        it('matches',function()
            assert.is_true(match)
          end)
        
      end)
    
    describe('Can remove path',function()
        local match
        local removed
        
        setup(function()
            local radix_tree = radix.new()
            radix_tree.add('abc')
            radix_tree.add('def')
            local radix_fetchers = {}
            radix_fetchers['equals'] = 'abc'
            radix_tree.match_parts(radix_fetchers)
            match = radix_tree.found_elements()['abc']
            radix_tree.remove('abc')
            radix_tree.match_parts(radix_fetchers)
            removed = radix_tree.found_elements()['abc']
          end)
        
        it('matches',function()
            assert.is_true(match)
          end)
        
        it('mismatches',function()
            assert.is_falsy(removed)
          end)
        
      end)
    
    describe('Can fetch equals',function()
        local match
        
        setup(function()
            local radix_tree = radix.new()
            radix_tree.add('abcdef')
            radix_tree.add('ddefghi')
            radix_tree.add('defghi')
            radix_tree.add('defghid')
            radix_tree.add('ddefghia')
            local radix_fetchers = {}
            radix_fetchers['equals'] = 'defghi'
            radix_tree.match_parts(radix_fetchers)
            match = function (word)
              return radix_tree.found_elements()[word]
            end
          end)
        
        it('matches',function()
            assert.is_true(match('defghi'))
          end)
        
        it('mismatches',function()
            assert.is_falsy(match('ddefghi'))
            assert.is_falsy(match('defghid'))
            assert.is_falsy(match('ddefghia'))
            assert.is_falsy(match('abcdef'))
          end)
        
      end)
    
    describe('Can fetch startsWith',function()
        local match
        
        setup(function()
            local radix_tree = radix.new()
            radix_tree.add('abcdef')
            radix_tree.add('defghi')
            radix_tree.add('abcghi')
            local radix_fetchers = {}
            radix_fetchers['startsWith'] = 'abc'
            radix_tree.match_parts(radix_fetchers)
            match = function (word)
              return radix_tree.found_elements()[word]
            end
          end)
        
        it('matches',function()
            assert.is_true(match('abcdef'))
            assert.is_true(match('abcghi'))
          end)
        
        it('mismatches',function()
            assert.is_falsy(match('abc'))
            assert.is_falsy(match('defghi'))
          end)
        
      end)
    
    describe('Can fetch contains',function()
        local match
        
        setup(function()
            local radix_tree = radix.new()
            radix_tree.add('abcdef')
            radix_tree.add('fgabcdef')
            radix_tree.add('abcdefg')
            radix_tree.add('defghi')
            radix_tree.add('abcfghi')
            local radix_fetchers = {}
            radix_fetchers['contains'] = 'fg'
            radix_tree.match_parts(radix_fetchers)
            match = function (word)
              return radix_tree.found_elements()[word]
            end
          end)
        
        it('matches',function()
            assert.is_true(match('defghi'))
            assert.is_true(match('abcfghi'))
            assert.is_true(match('fgabcdef'))
            assert.is_true(match('abcdefg'))
          end)
        
        it('mismatches',function()
            assert.is_falsy(match('fg'))
            assert.is_falsy(match('abcdef'))
          end)
        
      end)
    
    describe('Can fetch endsWith',function()
        local match
        
        setup(function()
            local radix_tree = radix.new()
            radix_tree.add('abcdeffg')
            radix_tree.add('defghi')
            radix_tree.add('abchifg')
            radix_tree.add('afbcfghi')
            local radix_fetchers = {}
            radix_fetchers['endsWith'] = 'fg'
            radix_tree.match_parts(radix_fetchers)
            match = function (word)
              return radix_tree.found_elements()[word]
            end
          end)
        
        it('matches',function()
            assert.is_true(match('abcdeffg'))
            assert.is_true(match('abchifg'))
          end)
        
        it('mismatches',function()
            assert.is_falsy(match('fg'))
            assert.is_falsy(match('defghi'))
            assert.is_falsy(match('afbcfghi'))
          end)
        
      end)
    
    describe('Can fetch startsWith + endsWith',function()
        local match
        
        setup(function()
            local radix_tree = radix.new()
            radix_tree.add('abcdeffg')
            radix_tree.add('defghi')
            radix_tree.add('abchifg')
            radix_tree.add('ahfbcfghi')
            radix_tree.add('ahi')
            local radix_fetchers = {}
            radix_fetchers['startsWith'] = 'ah'
            radix_fetchers['endsWith'] = 'hi'
            radix_tree.match_parts(radix_fetchers)
            match = function (word)
              return radix_tree.found_elements()[word]
            end
          end)
        
        it('matches',function()
            assert.is_true(match('ahfbcfghi'))
          end)
        
        it('mismatches',function()
            assert.is_falsy(match('a'))
            assert.is_falsy(match('hi'))
            assert.is_falsy(match('defghi'))
            assert.is_falsy(match('ahi'))
            assert.is_falsy(match('abcdeffg'))
          end)
        
      end)
    
    describe('Can fetch contains + endsWith',function()
        local match
        
        setup(function()
            local radix_tree = radix.new()
            radix_tree.add('hiabghcdeffhi')
            radix_tree.add('deghfghi')
            radix_tree.add('ahchifg')
            radix_tree.add('ahchifghi')
            radix_tree.add('ahfbcfghi')
            local radix_fetchers = {}
            radix_fetchers['contains'] = 'gh'
            radix_fetchers['endsWith'] = 'hi'
            radix_tree.match_parts(radix_fetchers)
            match = function (word)
              return radix_tree.found_elements()[word]
            end
          end)
        
        it('matches',function()
            assert.is_true(match('deghfghi'))
            assert.is_true(match('hiabghcdeffhi'))
          end)
        
        it('mismatches',function()
            assert.is_falsy(match('ahchifg'))
            assert.is_falsy(match('hi'))
            assert.is_falsy(match('gh'))
            assert.is_falsy(match('ahchifghi'))
            assert.is_falsy(match('ahchifg'))
            assert.is_falsy(match('ahfbcfghi'))
          end)
        
      end)
    
    describe('Can fetch startsWith + contains',function()
        local match
        
        setup(function()
            local radix_tree = radix.new()
            radix_tree.add('abcdeffg')
            radix_tree.add('defghi')
            radix_tree.add('ahchifg')
            radix_tree.add('ahchifghi')
            radix_tree.add('ahfbcfghi')
            radix_tree.add('ahia')
            local radix_fetchers = {}
            radix_fetchers['startsWith'] = 'ah'
            radix_fetchers['contains'] = 'hi'
            radix_tree.match_parts(radix_fetchers)
            match = function (word)
              return radix_tree.found_elements()[word]
            end
          end)
        
        it('matches',function()
            assert.is_true(match('ahfbcfghi'))
            assert.is_true(match('ahchifghi'))
            assert.is_true(match('ahchifg'))
          end)
        
        it('mismatches',function()
            assert.is_falsy(match('a'))
            assert.is_falsy(match('hi'))
            assert.is_falsy(match('defghi'))
            assert.is_falsy(match('ahia'))
            assert.is_falsy(match('abcdeffg'))
          end)
        
      end)
    
    describe('Can fetch startsWith + contains + endsWith',function()
        local match
        
        setup(function()
            local radix_tree = radix.new()
            radix_tree.add('defghi')
            radix_tree.add('ahchifg')
            radix_tree.add('ahicfg')
            radix_tree.add('ahfbcfghi')
            radix_tree.add('ahia')
            local radix_fetchers = {}
            radix_fetchers['startsWith'] = 'ah'
            radix_fetchers['contains'] = 'hi'
            radix_fetchers['endsWith'] = 'fg'
            radix_tree.match_parts(radix_fetchers)
            match = function (word)
              return radix_tree.found_elements()[word]
            end
          end)
        
        it('matches',function()
            assert.is_true(match('ahchifg'))
          end)
        
        it('mismatches',function()
            assert.is_falsy(match('ah'))
            assert.is_falsy(match('hi'))
            assert.is_falsy(match('ahicfg'))
            assert.is_falsy(match('defghi'))
            assert.is_falsy(match('ahfbcfghi'))
          end)
        
      end)
    
    
  end)
