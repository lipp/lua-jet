-- Implements a radix tree for the jet-daemon

local pairs = pairs
local print = print
local next = next
local type = type

local new = function()
  local j = {}
  
  -- the table that holds the radix_tree
  
  local radix_tree = {}
  
  -- elments that can be filled by several functions
  -- and be returned as set of possible hits
  
  local radix_elements = {}
  
  -- internal tree instance or table of tree instances
  -- used to hold parts of the tree that may be interesting afterwards
  
  local return_tree = {}

  -- this FSM is used for string comparison
  -- can evaluate if the radix tree contains or ends with a specific string

  local lookup_fsm
  lookup_fsm = function (wordpart, next_state, next_letter)
    if (wordpart:sub(next_state,next_state) ~= next_letter) then
      return false, 0
    end
    if (wordpart:len() == next_state) then
      return true, next_state
    else
      return false, next_state
    end
  end
  
  -- evaluate if the radix tree starts with a specific string
  -- returns pointer to subtree
  
  local root_lookup
  root_lookup = function( tree_instance, part)
    if part:len() < 1 then
      return_tree = tree_instance
    else
      local s = part:sub( 1, 1 )
      if type(tree_instance[s])=="table" then
        root_lookup( tree_instance[s], part:sub(2))
      end
    end
  end
  
  -- evaluate if the radix tree contains or ends with a specific string
  -- returns list of pointers to subtrees
  
  local leaf_lookup
  leaf_lookup = function( tree_instance, word, state, only_end)
    local next_state = state+1
    for k, v in pairs(tree_instance) do
      if type(v)=="table" then
        local hit, next_state = lookup_fsm(word, next_state, k)
        if (hit == true) then
          if only_end then
            if type(v[next(v)])=="boolean" then
              radix_elements[next(v)] = true
            end
          else
            table.insert(return_tree, v)
          end
        else
          leaf_lookup( v, word, next_state, only_end);
        end
      end
    end
  end
  
  -- takes a single tree or a list of trees
  -- traverses the trees and adds all elements to radix_elements
  
  local radix_traverse
  radix_traverse = function( tree_instance )
    for k, v in pairs(tree_instance) do
      if type(v)=="boolean" then
        radix_elements[k] = true
      elseif type(v)=="table" then
        radix_traverse( v );
      end
    end
  end
  
  -- adds a new element to the tree
  
  local add_to_tree
  add_to_tree = function( tree_instance, fullword, part )
    part = part or fullword;
    if part:len() < 1 then
      tree_instance[fullword]=true;
    else
      local s = part:sub( 1, 1 )
      if type(tree_instance[s])~="table" then
        tree_instance[s] = {};
      end
      add_to_tree( tree_instance[s], fullword, part:sub(2) )
    end
  end
  
  -- removes an element from the tree
  
  local remove_from_tree
  remove_from_tree = function( tree_instance, fullword, part )
    part = part or fullword;
    if part:len() < 1 then
      tree_instance[fullword]=nil;
    else
      local s = part:sub( 1, 1 )
      if type(tree_instance[s])~="table" then
        return
      end
      remove_from_tree( tree_instance[s], fullword, part:sub(2) )
    end
  end
  
  -- performs the respective actions for the parts of a fetcher
  -- that can be handled by a radix tree
  -- fills radix_elements with all hits that were found
  
  local match_parts
  match_parts = function (tree_instance, parts)
    if (parts['equals']) then
      return_tree = {}
      root_lookup(tree_instance, parts['equals'])
      if type(return_tree[next(return_tree)])=="boolean" then
        radix_elements[next(return_tree)] = true
      end
    else
      local temp_tree = tree_instance
      if (parts['startsWith']) then
        return_tree = {}
        root_lookup(temp_tree, parts['startsWith'])
        temp_tree = return_tree
      end
      if (parts['contains']) then
        return_tree = {}
        leaf_lookup(temp_tree, parts['contains'], 0, false)
        temp_tree = return_tree
      end
      if (parts['endsWith']) then
        return_tree = {}
        leaf_lookup(temp_tree, parts['endsWith'], 0, true)
        temp_tree = return_tree
      end
      if temp_tree then
        radix_traverse(temp_tree)
      end
    end
  end
  
  -- evaluates if the fetch operation can be handled
  -- completely or partially by the radix tree
  -- returns elements from the radix_tree if it can be handled
  -- and nil otherwise
  
  local get_possible_matches
  get_possible_matches = function (peer, params, fetch_id, is_case_insensitive)
    local involves_path_match = params.path
    local involves_value_match = params.value or params.valueField
    local level = 'impossible'
    local radix_expressions = {}
    
    if involves_path_match and not is_case_insensitive then
      for name,value in pairs(params.path) do
        if name == 'equals' or name == 'startsWith' or name == 'endsWith' or name == 'contains' then
          if radix_expressions[name] then
            level = 'impossible'
            break
          end
          radix_expressions[name] = value
          if level == 'partial_pending' or involves_value_match then
            level = 'partial'
          elseif level ~= 'partial' then
            level = 'all'
          end
        else
          if level == 'easy' or level == 'partial' then
            level = 'partial'
          else
            level = 'partial_pending'
          end
        end
      end
      if level == 'partial_pending' then
        level = 'impossible'
      end
    end
    
    if level ~= 'impossible' then
      radix_elements = {}
      match_parts(radix_tree, radix_expressions)
      return radix_elements
    else
      return nil
    end
  end
  
  j.add = function (word)
    add_to_tree(radix_tree, word)
  end
  j.remove = function (word)
    remove_from_tree(radix_tree, word)
  end
  j.get_possible_matches = get_possible_matches
  
  return j
end

return {
  new = new
}
