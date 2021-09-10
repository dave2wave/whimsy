# Reads LDAP ou=projects and extracts member rosters for PMCs
# (PMC status comes from committee-info.txt)
#
# Also reads LDAP ou=groups,dc=apache,dc=org to extract some non-PMCs
# This is to maintain compatibility with earlier output
#
# The contents cannot be used to determine LDAP group membership
#
# Creates JSON output with the following format:
#
# {
#   "lastTimestamp": "20160119171152Z", // most recent modifyTimestamp
#   "group_count": 123,
#   "roster_counts": {
#     "name": 1,
#     ///
#   },
#   "groups": {
#     "abdera": {
#       "modifyTimestamp": "20111204095436Z",
#       "roster_count": 123,
#       "roster": ["uid",
#       ...
#       ]
#     },
#     ...
#   },
# }
#

require_relative 'public_json_common'

entries = {}

# Dummy classes as Project class seems to be awkward to create easily
class MyProject
  attr_accessor :modifyTimestamp
  attr_accessor :createTimestamp
  attr_accessor :name
  attr_accessor :members
  attr_accessor :owners
end

class MyPerson
  attr_accessor :name

  def initialize(name)
    @name=name
  end
end

groups = ASF::Group.preload # for performance
projects = ASF::Project.preload

# Not projects but in original output
# TODO do we want them all?
# These will be extracted from groups if not in projects
EXTRAS = %w(apsite committers member concom infra security)

# These are the ones that will be generated
WANTED = ASF::Committee.pmcs.map(&:name) + EXTRAS

if projects.empty?
  Wunderbar.error "No results retrieved, output not created"
  exit 0
end
lastStamp = ''

# Add the non-project entries from the groups
ALREADY = projects.keys.map(&:name)
groups.select {|g| EXTRAS.include? g.name}.each do |group, data|
  next if ALREADY.include?(group.name)
  project = MyProject.new
  project.name = group.name
  project.createTimestamp = group.createTimestamp
  project.modifyTimestamp = group.modifyTimestamp
  project.members = group.members.map {|p| MyPerson.new(p.name)}
  project.owners = []
  projects[project] = []
end

roster_counts = Hash.new(0)
projects.keys.sort_by(&:name).each do |project|
  next unless WANTED.include? project.name
  m = []
  createTimestamp = project.createTimestamp
  modifyTimestamp = project.modifyTimestamp
  project.members.sort_by(&:name).each do |e|
    m << e.name
  end
  lastStamp = modifyTimestamp if modifyTimestamp > lastStamp
  entries[project.name] = {
    createTimestamp: createTimestamp,
    modifyTimestamp: modifyTimestamp,
    roster_count: m.size,
    roster: m
  }
  roster_counts[project.name] = m.size
end

info = {
  # Is there a use case for the last createTimestamp ?
  lastTimestamp: lastStamp,
  group_count: entries.size,
  roster_counts: roster_counts,
  groups: entries,
}

public_json_output(info)

if changed? and @old_file
  # for validating UIDs
  uids = ASF::Person.list().map(&:id)
  entries.each do |name, entry|
    entry[:roster].each do |id|
      Wunderbar.warn "#{name}: unknown uid '#{id}'" unless uids.include?(id)
    end
  end
end
