-- Implements a radix tree for the jet-daemon

local pairs = pairs
local next = next
local tinsert = table.insert
local tremove = table.remove

local new = function()
  local j = {}
  
  -- the table that holds the radix_tree
  j.radix_tree = {}
  
  -- elments that can be filled by several functions
  -- and be returned as set of possible hits
  j.radix_elements = {}
  
  -- internal tree instance or table of tree instances
  -- used to hold parts of the tree that may be interesting afterwards
  j.return_tree = {}
  
  -- this FSM is used for string comparison
  -- can evaluate if the radix tree contains or ends with a specific string
  local lookup_fsm = function (wordpart,next_state,next_letter)
    if wordpart:sub(next_state,next_state) ~= next_letter then
      if wordpart:sub(1,1) ~= next_letter then
        return false,0
      else
        return false,1
      end
    end
    if #wordpart == next_state then
      return true,next_state
    else
      return false,next_state
    end
  end
  
  -- evaluate if the radix tree starts with a specific string
  -- returns pointer to subtree
  local root_lookup
  root_lookup = function(tree_instance,part)
    if #part == 0 then
      j.return_tree = tree_instance
    else
      local s = part:sub(1,1)
      if tree_instance and tree_instance[s] ~= true then
        root_lookup(tree_instance[s], part:sub(2))
      end
    end
  end
  
  -- evaluate if the radix tree contains or ends with a specific string
  -- returns list of pointers to subtrees
  local leaf_lookup
  leaf_lookup = function(tree_instance,word,state)
    local next_state = state + 1
    if tree_instance then
      for k,v in pairs(tree_instance) do
        if v ~= true then
          local hit,next_state = lookup_fsm(word,next_state,k)
          if hit == true then
            tinsert(j.return_tree,v)
          else
            leaf_lookup(v,word,next_state)
          end
        end
      end
    end
  end
  
  -- takes a single tree or a list of trees
  -- traverses the trees and adds all elements to j.radix_elements
  local radix_traverse
  radix_traverse = function(tree_instance)
    for k,v in pairs(tree_instance) do
      if v == true then
        j.radix_elements[k] = true
      elseif v ~= true then
        radix_traverse(v)
      end
    end
  end
  
  -- adds a new element to the tree
  local add_to_tree = function(word)
    local t = j.radix_tree
    for char in word:gfind('.') do
      if t[char] == true or t[char] == nil then
        t[char] = {}
      end
      t = t[char]
    end
    t[word] = true
  end
  
  
  -- removes an element from the tree
  local remove_from_tree = function(word)
    local t = j.radix_tree
    for char in word:gfind('.') do
      if t[char] == true then
        return
      end
      t = t[char]
    end
    t[word] = nil
  end
  
  -- performs the respective actions for the parts of a fetcher
  -- that can be handled by a radix tree
  -- fills j.radix_elements with all hits that were found
  local match_parts = function(tree_instance,parts)
    j.radix_elements = {}
    if parts['equals'] then
      j.return_tree = {}
      root_lookup(tree_instance,parts['equals'])
      if j.return_tree[parts['equals']] == true then
        j.radix_elements[parts['equals']] = true
      end
    else
      local temp_tree = tree_instance
      if parts['startsWith'] then
        j.return_tree = {}
        root_lookup(temp_tree,parts['startsWith'])
        temp_tree = j.return_tree
      end
      if parts['contains'] then
        j.return_tree = {}
        leaf_lookup(temp_tree,parts['contains'],0)
        temp_tree = j.return_tree
      end
      if parts['endsWith'] then
        j.return_tree = {}
        leaf_lookup(temp_tree,parts['endsWith'],0)
        for k,t in pairs(j.return_tree) do
          for _,v in pairs(t) do
            if v ~= true then
              j.return_tree[k] = nil
              break
            end
          end
        end
        temp_tree = j.return_tree
      end
      if temp_tree then
        radix_traverse(temp_tree)
      end
    end
  end
  
  -- evaluates if the fetch operation can be handled
  -- completely or partially by the radix tree
  -- returns elements from the j.radix_tree if it can be handled
  -- and nil otherwise
  local get_possible_matches = function(peer,params,fetch_id,is_case_insensitive)
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
      match_parts(j.radix_tree,radix_expressions)
      return j.radix_elements
    else
      return nil
    end
  end
  
  j.add = function(word)
    add_to_tree(word)
  end
  j.remove = function(word)
    remove_from_tree(word)
  end
  j.get_possible_matches = get_possible_matches
  
  -- for unit testing
  
  j.match_parts = function(parts,xxx)
    match_parts(j.radix_tree,parts,xxx)
  end
  j.found_elements = function()
    return j.radix_elements
  end
  
  return j
end

return {
  new = new
}
