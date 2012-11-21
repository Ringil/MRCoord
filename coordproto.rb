require 'sinatra'
require 'data_mapper'
require 'json'

enable :sessions

SITE_TITLE = "Community MapReduce"
DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/coord.db")

helpers do
	include Rack::Utils
	alias_method :h, :escape_html
end


######################################
#             Database Model         #
######################################
class Job
	include DataMapper::Resource
	property :id, 			Serial						#Job id
	property :desc, 		Text,	:required => true 	#Description of the job
	property :owner, 		Text, 	:required => true   #Whomever created the MapReduce job ie. a researcher
	property :mapFunc,		Text,	:required => true
	property :reduceFunc,	Text,	:required => true 
	property :started,		Boolean, :default => false
	has n, :workers
	has n, :dataChunks
end


class Worker
	include DataMapper::Resource
	property 	:id,		Serial 		#This will be a client/workers unique ID for this job
	property	:dataID,	Integer,	:required => true
	belongs_to 	:job
end

class DataChunk
	include DataMapper::Resource
	property :id, 			Serial
	property :location, 	String,	 :required => true	#Location of the piece of data ie. the link
	property :numWorkers,	Integer, :default => 0		#Number of workers who have this piece of data
	property :finished,		Boolean, :default => false 	#Check if we already have the results for this chunk
	belongs_to :job

	#Decides the next chunk to be used in an round-robin scheme.
	def self.nextChunk
		#Chooses the first chunk that has not finished and has the least amount of workers.
		first(:finished => false, :order => [:numWorkers.asc])
	end	
end

DataMapper.finalize.auto_migrate!

#This is just some dummy input for the db to test stuff
test = {
	:desc => "Random description",
	:owner => "Ted Copplestein",
	:dataChunks => [
		{
			:location => "www.otherdatastore.com/chunk1",
			:numWorkers => 0,
			:finished => false
		},
	]
}
job = Job.first_or_create(test)


test2 = {
	:desc => "Dummy desc",
	:owner => "Mark Vensawhl",
	:dataChunks => [
		{
			:location => "www.datastore.com/chunk1",
			:numWorkers => 0,
			:finished => false
		},
	]
}
blah = Job.first_or_create(test2)

#############################################
#             MR Coordinator                #
#############################################
get '/' do
	@jobs = Job.all(:order => :id.desc)
	erb :home
end

post '/register_job' do
	jobJSON = JSON.parse(request.body.read.to_s)

	newjob = {
		:desc => jobJSON['jobName'],
		:owner => "This is a default value until we change the json format",
		:mapFunc => jobJSON['map'],
		:reduceFunc => jobJSON['reduce'],
		
	}
	#need to parse json file of format
# 	post data (JSON): 
# {
#   jobName: "Some job name",
#   input: "http://datastore",
#   output: "http://datastore",
#   map: "map_function_goes_here",
#   reduce: "reduce_function_goes_here"
# }
# response (JSON):
# {
#   status: "READY",
#   jobID: "job1234"
# }
end

post '/start_job' do
# json file with the job id to start
end

post '/:id/submit_map_output' do
# post data: 
# {
#    {key: "some_key1", value: ["value1", "value2" ]},
#    {key: "some_key2", value:  ["value1"]},
#    {key: "some_key3", value:  ["value3", "value4"]}
# }
end

get '/:id/worker' do
	#Retrieve the job based on the id
	job = Job.get(params[:id])
	unless job
		redirect '/' #If you can't find the job with that id redirect back to the main page
	end

	nextJob = job.dataChunks.nextChunk #Find next piece of data that needs work

	worker = job.workers.create(:dataID => nextJob.id) #Add a worker entry to the job
	
	#Create JSON response with needed info
	content_type :json
	{
		:url => nextJob.location,
		:fnLocation => "http://coordinator/jobID/map.js",
		:output => "http://coordinator/jobID/submit_map_output",
		:workID => worker.id
	}.to_json
end